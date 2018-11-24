
from __future__ import print_function
from IPython import embed


def fib(n):
	assert n >= 0
	if n in {0, 1}:
		return 1
	else:
		return fib(n-2) + fib(n-1)


def print_table(n):
	for i in range(n):
		print(fib(i))


class Test(object):
	def some(self):
		def f(): pass
	x = 12



import ast # https://greentreesnakes.readthedocs.io/en/latest/index.html


class Symbol(object):
	def __init__(self, name=None, line=None, kind=None, file=None):
		self.name = name
		self.file = file
		self.line = line # 1 based
		self.kind = kind

	def __str__(self):
		return '%s [%s]' % (self.name, self.kind)


def qualify(qualifier, symbols):
	for s in symbols:
		s.name = qualifier + '.' + s.name
	return symbols


def filerize(file, symbols):
	for s in symbols:
		s.file = file
	return symbols


def get_symbols_in_Module(node):

	symbols = []

	class V(ast.NodeVisitor):
		def visit_FunctionDef(self, node):
			symbols.append(Symbol(node.name, node.lineno, 'function'))
			symbols.extend(qualify(node.name, get_symbols_in_FunctionDef(node.body)))

		def visit_ClassDef(self, node):
			symbols.append(Symbol(node.name, node.lineno, 'class'))
			symbols.extend(qualify(node.name, get_symbols_in_ClassDef(node.body)))

		def visit_Assign(self, node):
			for t in node.targets:
				for i in ast.walk(t):
					if isinstance(i, ast.Name):
						symbols.append(Symbol(i.id, node.lineno, 'variable'))

	V().visit(node)
	return symbols


def get_symbols_in_FunctionDef(body):

	symbols = []

	class V(ast.NodeVisitor):
		def visit_ClassDef(self, node):
			symbols.append(Symbol(node.name, node.lineno, 'class'))
			symbols.extend(qualify(node.name, get_symbols_in_ClassDef(node.body)))

	for i in body:
		V().visit(i)
	return symbols


def get_symbols_in_ClassDef(body):
	return [ j for i in body for j in get_symbols_in_Module(i) ]


def create_tag_entries(symbols):
	# todo might add tag for sorted for binary search, but not sure if that is always at the top?
	return sorted([
			'%s\t%s\t%d;" %s' % (i.name, i.file, i.line, i.kind)
			for i in symbols
		])


def get_symbols_in_folders(folders):
	return [ s for f in folders for s in get_symbols_in_folder(f) ]


def get_symbols_in_folder(folder):

	import os
	import os.path

	symbols = []

	for f in os.listdir(folder):
		if os.path.isdir(f):
			if '.' not in f:
				symbols.extend(qualify(f, get_symbols_in_folder(os.path.join(folder, f))))
		elif f == '__init__.py':
			symbols.extend(get_symbols_in_file(os.path.join(folder, f)))
		elif f.endswith('.py'):
			symbols.extend(qualify(f[:-3], get_symbols_in_file(os.path.join(folder, f))))

	return symbols


def get_symbols_in_file(file):
	return filerize(file, get_symbols_in_Module(ast.parse(open(file).read())))


symbols = get_symbols_in_folder('.')
print('\n'.join(map(str, sorted(symbols, key=lambda s: s.name.lower()))))
open('.tags', 'wt').write('\n'.join(create_tag_entries(symbols)))
