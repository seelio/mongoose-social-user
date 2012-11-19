{spawn, exec} = require 'child_process'

build = (watch) ->
  options = ['-c', '-o', 'lib', 'src']
  if watch is true
    options[0] = '-cw'
  watcher = spawn 'coffee', options
  watcher.stdout.on 'data', (data) ->
    console.log data.toString().trim()
  watcher.stderr.on 'data', (data) ->
    console.log data.toString().trim()
    watcher = spawn 'coffee.cmd', options
    watcher.stdout.on 'data', (data) ->
      console.log data.toString().trim()
    watcher.stderr.on 'data', (data) ->
      console.log data.toString().trim()

task 'build', 'build the project', (watch) ->
  build watch

task 'watch', 'watch the libs and controllers folders', () ->
  build true