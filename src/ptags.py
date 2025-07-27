from __future__ import annotations

import functools
import sys
from collections.abc import Iterable, Iterator, Sequence
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import dataclass
from enum import Enum
from multiprocessing import cpu_count
from pathlib import Path
from typing import TextIO, assert_never, override

import tree_sitter_python
import typer
from tabulate import tabulate
from tree_sitter import Language, Node, Parser, Query, QueryCursor


class Kind(Enum):
    function = "function"
    classdef = "class"
    variable = "variable"
    type_alias = "type alias"


@dataclass(frozen=True)
class Symbol(object):
    qualifiers: tuple[str, ...]
    line: int  # 1-based
    kind: Kind
    file: Path

    @property
    def name(self) -> str:
        return ".".join(self.qualifiers)

    @property
    def kind_str(self) -> str:
        return str(self.kind.value)

    @override
    def __str__(self):
        return "%s [%s]" % (self.name, self.kind)


def get_ts_query_for_kind(kind: Kind) -> str:
    match kind:
        case Kind.function:
            return f"(function_definition name: (identifier) @{kind.name})"
        case Kind.classdef:
            return f"(class_definition name: (identifier) @{kind.name})"
        case Kind.variable:
            return f"(assignment left: (identifier) @{kind.name})"
        case Kind.type_alias:
            return f"(type_alias_statement (type (identifier) @{kind.name}))"
        case _ as never:
            assert_never(never)


def get_ts_queries() -> str:
    return "\n".join(get_ts_query_for_kind(k) for k in Kind)


@functools.cache
def ts_setup() -> tuple[Parser, QueryCursor]:
    language = Language(tree_sitter_python.language())
    parser = Parser(language)
    query = Query(language, get_ts_queries())
    query_cursor = QueryCursor(query)
    return parser, query_cursor


def parse_and_capture(file: Path) -> dict[str, list[Node]]:
    parser, query = ts_setup()
    source = file.read_text().encode("utf8")
    tree = parser.parse(source)
    return query.captures(tree.root_node)


def named_parent_block_nodes_from_node(node: Node) -> tuple[list[str], list[Node]]:
    names: list[str] = []
    nodes: list[Node] = []
    at = node.parent
    while at is not None:
        if at.type == "block" and at.parent is not None:
            maybe_name = at.parent.child_by_field_name("name")
            if maybe_name is not None and maybe_name.text is not None:
                names.append(maybe_name.text.decode("utf8"))
                nodes.append(at.parent)
        at = at.parent
    return names, nodes


def get_symbol_from_capture(
    node: Node, name: str, file: Path, file_scope: tuple[str, ...]
) -> None | Symbol:
    if node.text is None:
        return None
    identifier = node.text.decode("utf8")
    kind = Kind[name]
    parent_names, parents = named_parent_block_nodes_from_node(node)

    match kind:
        case Kind.function:
            pass
        case Kind.classdef:
            pass
        case Kind.variable:
            for n in parents:
                if n.type == "function_definition":
                    return None
                if n.type == "class_definition":
                    break
        case Kind.type_alias:
            pass  # NOTE they can only be used on module or class level, so we dont have to filter
        case _ as never:
            assert_never(never)

    scope = tuple(reversed(parent_names))

    return Symbol(
        file_scope + scope + (identifier,),
        node.start_point[0] + 1,
        kind,
        file,
    )


def get_symbols_in_file(file: Path, file_scope: tuple[str, ...]) -> list[Symbol]:
    # NOTE we dont warn about syntax errors in files if there are any
    candidates = parse_and_capture(file)
    maybe_symbols = [
        get_symbol_from_capture(node, name, file, file_scope)
        for (name, nodes) in candidates.items()
        for node in nodes
    ]
    return [s for s in maybe_symbols if s is not None]


def get_scope_from_file(file: Path, base: Path) -> tuple[str, ...]:
    [*parts, last] = file.relative_to(base).parts
    match last:
        case "__init__.py":
            return tuple(parts)
        case _:
            return tuple(parts + [file.stem])


def get_flat_sources(sources: Sequence[Path]) -> Iterator[tuple[Path, tuple[str, ...]]]:
    """yields tuples of file and scope"""
    for source in sources:
        if source.is_file():
            yield source, ()
        elif source.is_dir():
            for file in source.glob("**/*.py"):
                yield file, get_scope_from_file(file, source)


def get_symbols_in_sources(sources: Sequence[Path]) -> Iterable[Symbol]:
    ts_setup()
    with ProcessPoolExecutor(max_workers=cpu_count()) as pool:
        futures = [
            pool.submit(get_symbols_in_file, file, scope)
            for file, scope in get_flat_sources(sources)
        ]
        for future in as_completed(futures):
            yield from future.result()


# NOTE probably useful for profiling and debugging
def get_symbols_in_sources_single_process(sources: Sequence[Path]) -> Iterable[Symbol]:
    for file, scope in get_flat_sources(sources):
        yield from get_symbols_in_file(file, scope)


class Format(str, Enum):
    human = "human"
    ctags = "ctags"
    telescope = "telescope"


def make_entries(format: Format, symbols: Iterable[Symbol], out: TextIO):
    match format:
        case Format.human:
            make_human_entries(list(symbols), out)
        case Format.ctags:
            make_tag_entries(list(symbols), out)
        case Format.telescope:
            make_telescope_entries(symbols, out)
        case _ as never:
            assert_never(never)


def make_human_entries(symbols: Sequence[Symbol], out: TextIO):
    headers = ["location", "kind", "name"]
    data = [[f"{s.file}:{s.line}", f"{s.kind_str}", f"{s.name}"] for s in symbols]
    out.write(tabulate(data, headers=headers) + "\n")
    out.write(f"Found {len(symbols)} symbols.\n")


def make_tag_entries(symbols: Sequence[Symbol], out: TextIO):
    # NOTE from vim's documentation I'm not sure if that has to be first line,
    # or still sorted, also not sure if I 'case-fold' sorted correctly
    header = ["!_TAG_FILE_SORTED\t2\tcase-fold sorted"]
    entries = [
        '%s\t%s\t%d;" %s' % (i.name, i.file, i.line, i.kind_str)
        for i in sorted(symbols, key=lambda s: s.name.lower())
    ]
    out.write("\n".join(header + entries))
    out.write("\n")


def make_telescope_entries(symbols: Iterable[Symbol], out: TextIO):
    for s in symbols:
        out.write(
            "\x00".join(
                [
                    s.name,
                    str(s.line),
                    s.kind_str,
                    str(s.file),
                ]
            )
            + "\n"
        )
    out.write("\n")


cli = typer.Typer(
    no_args_is_help=True,
    pretty_exceptions_enable=False,
)


@cli.command()
def main(sources: list[Path], format: Format = Format.human):
    symbols = get_symbols_in_sources(sources)
    make_entries(format, symbols, sys.stdout)


if __name__ == "__main__":
    cli()
