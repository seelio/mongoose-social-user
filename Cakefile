{spawn, exec} = require 'child_process'

build = (watch) ->
  folders = ['test/', {s: 'src/', o: 'lib/'}]
  buildFolder folder, watch for folder in folders

buildFolder = (folder, watch) ->
  if typeof folder is 'string'
    options = ['-c', folder]
  else
    options = ['-c', '-o', folder.o, folder.s]
  if watch is true
    options[0] = '-cw'
  watcher = spawn 'coffee', options
  watcher.stdout.on 'data', (data) ->
    console.log data.toString().trim()
  watcher.stderr.on 'data', (data) ->
    console.log data.toString().trim()
    watcher = spawn 'node_modules\\.bin\\coffee.cmd', options
    watcher.stdout.on 'data', (data) ->
      console.log data.toString().trim()
    watcher.stderr.on 'data', (data) ->
      console.log data.toString().trim()

task 'build', 'build the project', (watch) ->
  build watch

task 'watch', 'watch the libs and controllers folders', () ->
  build true
