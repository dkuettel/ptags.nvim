from python:2

run apt-get -yqq update
run apt-get -yqq install zsh

run pip install ipython
run pip install click

copy ptags.py /app/ptags.py
