# todo
# - out=- works because - is technically a writeable file, but we should treat it differently
# - docopt for parsing and another one for dispatch instead of click?
# - ctrlp custom? useful would be: Test,module; multilevel search expressions
#   see https://github.com/kien/ctrlp.vim/tree/extensions
# - options if/how nested functions and classes are listed or not
# - options to also include non-qualified entries
# - respect PYTHONPATH or whatever python uses to search all relevant locations?

import time
import os
import os.path
import uuid
import ast  # https://greentreesnakes.readthedocs.io/en/latest/index.html
import click


class Symbol(object):
    def __init__(self, name=None, line=None, kind=None, file=None):
        self.name = name
        self.file = file
        self.line = line  # 1 based
        self.kind = kind

    def __str__(self):
        return "%s [%s]" % (self.name, self.kind)


def qualify(qualifier, symbols):
    for s in symbols:
        s.name = qualifier + "." + s.name
    return symbols


def filerize(file, symbols):
    for s in symbols:
        s.file = file
    return symbols


def get_symbols_in_Module(node):

    symbols = []

    class V(ast.NodeVisitor):
        def visit_FunctionDef(self, node):
            symbols.append(Symbol(node.name, node.lineno, "function"))
            symbols.extend(qualify(node.name, get_symbols_in_FunctionDef(node.body)))

        def visit_ClassDef(self, node):
            symbols.append(Symbol(node.name, node.lineno, "class"))
            symbols.extend(qualify(node.name, get_symbols_in_ClassDef(node.body)))

        def visit_Assign(self, node):
            for t in node.targets:
                for i in ast.walk(t):
                    if isinstance(i, ast.Name):
                        symbols.append(Symbol(i.id, node.lineno, "variable"))

    V().visit(node)
    return symbols


def get_symbols_in_FunctionDef(body):

    symbols = []

    class V(ast.NodeVisitor):
        def visit_ClassDef(self, node):
            symbols.append(Symbol(node.name, node.lineno, "class"))
            symbols.extend(qualify(node.name, get_symbols_in_ClassDef(node.body)))

    for i in body:
        V().visit(i)
    return symbols


def get_symbols_in_ClassDef(body):
    return [j for i in body for j in get_symbols_in_Module(i)]


def create_tag_entries(symbols):
    entries = [
        '%s\t%s\t%d;" %s' % (i.name, i.file, i.line, i.kind)
        for i in sorted(symbols, key=lambda s: s.name.lower())
    ]
    # from vim's documentation I'm not sure if that has to be the first line, or still sorted
    # I'm also not sure I do 'case-fold sorted' correctly
    entries.insert(0, "!_TAG_FILE_SORTED\t2\tcase-fold sorted")
    return entries


def get_symbols_in_folders(folders):
    return [s for f in folders for s in get_symbols_in_folder(f)]


def get_symbols_in_folder(folder):

    symbols = []

    for f in os.listdir(folder):
        if os.path.isdir(os.path.join(folder, f)):
            if "." not in f:
                symbols.extend(
                    qualify(f, get_symbols_in_folder(os.path.join(folder, f)))
                )
        elif f == "__init__.py":
            symbols.extend(get_symbols_in_file(os.path.join(folder, f)))
        elif f.endswith(".py"):
            symbols.extend(
                qualify(f[:-3], get_symbols_in_file(os.path.join(folder, f)))
            )
        else:
            pass

    return symbols


def get_symbols_in_file(file):
    try:
        t = ast.parse(open(file).read(), filename=file)
    except SyntaxError as e:
        print(e)
        return []
    return filerize(file, get_symbols_in_Module(t))


@click.command()
@click.option(
    "--out",
    "-o",
    default=".tags",
    type=click.Path(writable=True),
    help="output tag file",
    show_default=True,
)
@click.option(
    "--loop/--no-loop",
    "-l/",
    default=False,
    help="repeatedly update tags",
    show_default=True,
)
@click.option(
    "--interval",
    "-i",
    default=10.0,
    help="update tags every X seconds",
    show_default=True,
)
@click.option(
    "--atomic/--no-atomic",
    "-a/",
    default=True,
    help="update tag file atomically (write to unique temporary file and then atomically replace target tag file)",
    show_default=True,
)
@click.option(
    "--quiet/--no-quiet",
    "-q/",
    default=False,
    help="suppress all output to stdout",
    show_default=True,
)
@click.argument("folders", nargs=-1, type=click.Path(exists=True))
def main(out, loop, interval, atomic, quiet, folders):

    if folders == ():
        folders = (".",)

    if quiet:
        print = lambda *args, **kwargs: None
    else:
        print = __builtins__.print

    if out == "-":
        write_entries = __builtins__.print
    else:
        if atomic:
            # in docker os.getpid() is not unique, usually 1
            tout = f"{out}-generating-{uuid.uuid4().hex}"

            def write_entries(entries):
                try:
                    open(tout, "wt").write(entries)
                    os.rename(tout, out)
                finally:
                    if os.path.exists(tout):
                        os.remove(tout)

        else:

            def write_entries(entries):
                open(out, "wt").write(entries)

    while True:

        dt = time.time()
        print("scanning ...", end="")
        symbols = get_symbols_in_folders(folders)
        print(" found %d symbols (%d ms)" % (len(symbols), (time.time() - dt) * 1000))

        entries = create_tag_entries(symbols)
        entries = "\n".join(entries)

        write_entries(entries)

        if loop:
            time.sleep(interval)
        else:
            break


if __name__ == "__main__":
    main()
