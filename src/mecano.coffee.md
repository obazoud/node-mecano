
    fs = require 'fs'
    path = require 'path'
    url = require 'url'
    util = require 'util'
    each = require 'each'
    eco = require 'eco'
    exec = require 'superexec'
    request = require 'request'
    Ftp = require 'jsftp'
    ldap = require 'ldapjs'
    ldap_client = require 'ldapjs/lib/client/client'
    {EventEmitter} = require 'events'

    conditions = require './conditions'
    misc = require './misc'
    child = require './child'
    curl = require './curl'

Mecano gather a set of functions usually used during system deployment. All the functions share a 
common API with flexible options.

Functions include "copy", "download", "exec", "extract", "git", "link", "mkdir", "move", "remove", "render", "service", "write". They all share common usages and philosophies:   
*   Run actions both locally and remotely over SSH.   
*   Ability to see if an action had an effect through the second argument provided in the callback.   
*   Common API with options and callback arguments and calling the callback with an error and the number of affected actions.   
*   Run one or multiple actions depending on option argument being an object or an array of objects.   

    mecano = module.exports = 

`chmod([goptions], options, callback)`
--------------------------------------

Change the file permissions of a file.

`options`           Command options include:   
*   `destination`   Where the file or directory is copied.
*   `mode`          Permissions of the file or the parent directory
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   
*   `log`           Function called with a log related messages.   

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `modified`      Number of files with modified permissions.

    chmod: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, modified) ->
        callback err, modified if callback
        result.end err, modified
      misc.options options, (err, options) ->
        return finish err if err
        modified = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Validate parameters
          {ssh, destination, mode} = options
          return next new Error "Missing destination: #{destination}" unless destination
          options.log? "Stat #{destination}"
          misc.file.stat ssh, destination, (err, stat) ->
            return next err if err
            return next() if misc.file.cmpmod stat.mode, mode
            options.log? "Change mode to #{mode}"
            misc.file.chmod ssh, destination, mode, (err) ->
              return next err if err
              modified++
              next()
        .on 'both', (err) ->
          finish err, modified

`chmod([goptions], options, callback)`
--------------------------------------

Change the file permissions of a file.

`options`           Command options include:   
*   `destination`   Where the file or directory is copied.
*   `mode`          Permissions of the file or the parent directory
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   
*   `log`           Function called with a log related messages.   

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `modified`      Number of files with modified permissions.

    chown: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, modified) ->
        callback err, modified if callback
        result.end err, modified
      misc.options options, (err, options) ->
        return finish err if err
        modified = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Validate parameters
          {ssh, destination, uid, gid} = options
          return next new Error "Missing destination: #{destination}" unless destination
          return next() unless uid and gid
          options.log? "Stat #{destination}"
          misc.file.stat ssh, destination, (err, stat) ->
            return next err if err
            return next() if stat.uid is uid and stat.gid is gid
            options.log? "Change uid from #{stat.uid} to #{uid}" if stat.uid isnt uid
            options.log? "Change gid from #{stat.gid} to #{gid}" if stat.gid isnt gid
            misc.file.chown ssh, destination, uid, gid, (err) ->
              return next() err if err
              modified++
              next()
        .on 'both', (err) ->
          finish err, modified

`cp` `copy([goptions], options, callback)`
------------------------------------------

Copy a file. The behavior is similar to the one of the `cp` 
Unix utility. Copying a file over an existing file will 
overwrite it.

`options`           Command options include:   
*   `source`        The file or directory to copy.
*   `destination`   Where the file or directory is copied.
*   `not_if_exists` Equals destination if true.
*   `mode`          Permissions of the file or the parent directory
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `copied`        Number of files or parent directories copied.

Todo:
*   preserve permissions if `mode` is `true`

    copy: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      misc.options options, (err, options) ->
        return callback err if err
        copied = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Validate parameters
          return next new Error 'Missing source' unless options.source
          return next new Error 'Missing destination' unless options.destination
          # return next new Error 'SSH not yet supported' if options.ssh
          # Cancel action if destination exists ? really ? no md5 comparaison, strange
          options.not_if_exists = options.destination if options.not_if_exists is true
          # Start real work
          conditions.all options, next, ->
            modified = false
            srcStat = null
            dstStat = null
            options.log? "Stat source file"
            misc.file.stat options.ssh, options.source, (err, stat) ->
              # Source must exists
              return next err if err
              srcStat = stat
              options.log? "Stat destination file"
              misc.file.stat options.ssh, options.destination, (err, stat) ->
                return next err if err and err.code isnt 'ENOENT'
                dstStat = stat
                sourceEndWithSlash = options.source.lastIndexOf('/') is options.source.length - 1
                if srcStat.isDirectory() and dstStat and not sourceEndWithSlash
                  options.destination = path.resolve options.destination, path.basename options.source
                if srcStat.isDirectory() then directory(options.source, next) else copy(options.source, next)
            # Copy a directory
            directory = (dir, callback) ->
              options.log? "Source is a directory"
              each()
              .files("#{dir}/**")
              .on 'item', (file, next) ->
                copy file, next
              .on 'both', callback
            copy = (source, callback) ->
              if srcStat.isDirectory()
                destination = path.resolve options.destination, path.relative options.source, source
              else if not srcStat.isDirectory() and dstStat?.isDirectory()
                destination = path.resolve options.destination, path.basename source
              else
                destination = options.destination
              misc.file.stat options.ssh, source, (err, stat) ->
                return callback err if err
                if stat.isDirectory()
                then do_copy_dir source, destination
                else do_copy_file source, destination
              do_copy_dir = (source, destination) ->
                return callback() if source is options.source
                options.log? "Create directory #{destination}"
                # todo, add permission
                misc.file.mkdir options.ssh, destination, (err) ->
                  return callback() if err?.code is 'EEXIST'
                  return callback err if err
                  modified = true
                  do_end()
              # Copy a file
              do_copy_file = (source, destination) ->
                misc.file.compare options.ssh, [source, destination], (err, md5) ->
                  # Destination may not exists
                  return callback err if err and err.message.indexOf('Does not exist') isnt 0
                  # File are the same, we can skip copying
                  return do_chown destination if md5
                  # Copy
                  s = (ssh, callback) ->
                    unless ssh
                    then callback null, fs
                    else options.ssh.sftp callback
                  s options.ssh, (err, fs) ->
                      options.log? "Copy file from #{source} into #{destination}"
                      rs = fs.createReadStream source
                      ws = rs.pipe fs.createWriteStream destination
                      ws.on 'close', ->
                        fs.end() if fs.end
                        modified = true
                        do_chown destination
                      ws.on 'error', callback
              do_chown = (destination) ->
                return do_chmod() if not options.uid and not options.gid
                mecano.chown
                  ssh: options.ssh
                  log: options.log
                  destination: destination
                  uid: options.uid
                  gid: options.gid
                , (err, chowned) ->
                  return callback err if err
                  modified = chowned if chowned
                  do_chmod()
              do_chmod = (destination) ->
                return do_end() if not options.mode
                mecano.chmod
                  ssh: options.ssh
                  log: options.log
                  destination: options.destination
                  mode: options.mode
                , (err, chmoded) ->
                  return callback err if err
                  modified = chmoded if chmoded
                  do_end()
              do_end = ->
                copied++ if modified
                callback()
        .on 'both', (err) ->
          callback err, copied

`download([goptions], options, callback)`
-----------------------------------------

Download files using various protocols.

When executed locally: the `http` protocol is handled 
with the "request" module; the `ftp` protocol is handled 
with the "jsftp"; the `file` protocol is handle with the navite 
`fs` module.

`options`           Command options include:   
*   `source`        File, HTTP URL, FTP, GIT repository. File is the default protocol if source is provided without any.   
*   `destination`   Path where the file is downloaded.   
*   `force`         Overwrite destination file if it exists.   
*   `stdout`        Writable Stream in which commands output will be piped.   
*   `stderr`        Writable Stream in which commands error will be piped.   

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `downloaded`    Number of downloaded files

File example
```coffee
mecano.download
  source: 'file://path/to/something'
  destination: 'node-sigar.tgz'
, (err, downloaded) -> ...
```

HTTP example
```coffee
mecano.download
  source: 'https://github.com/wdavidw/node-sigar/tarball/v0.0.1'
  destination: 'node-sigar.tgz'
, (err, downloaded) -> ...
```

FTP example
```coffee
mecano.download
  source: 'ftp://myhost.com:3334/wdavidw/node-sigar/tarball/v0.0.1'
  destination: 'node-sigar.tgz'
  user: "johndoe",
  pass: "12345"
, (err, downloaded) -> ...
```

    download: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, downloaded) ->
        callback err, downloaded if callback
        result.end err, downloaded
      misc.options options, (err, options) ->
        return finish err if err
        downloaded = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Validate parameters
          {destination, source, md5sum} = options
          # md5sum is used to validate the download
          return next new Error "Missing source: #{source}" unless source
          return next new Error "Missing destination: #{destination}" unless destination
          options.force ?= false
          stageDestination = "#{destination}.#{Date.now()}#{Math.round(Math.random()*1000)}"
          # Start real work
          prepare = () ->
            options.log? "Check if destination exists"
            # Note about next line: ssh might be null with file, not very clear
            misc.file.exists options.ssh, destination, (err, exists) ->
              # If we are forcing
              if options.force
                # Note, we should be able to move this before the "exists" check just above
                # because we don't seem to use. Maybe it still here because we were
                # expecting to remove the existing destination before downloading.
                download()
              # If the file exists and we have a checksum to compare and we are not forcing
              else if exists and md5sum
                # then we compute the checksum of the file
                misc.file.hash options.ssh, destination, 'md5', (err, hash) ->
                  return next err if err
                  # And compare with the checksum provided by the user
                  return next() if hash is md5sum
                  misc.file.unlink options.ssh, destination, (err) ->
                    return next err if err
                    download()
              # Get the checksum of the current file
              else if exists
                download()
              else download()
          download = () ->
            options.log? "Download the source"
            u = url.parse source
            if options.ssh
              if u.protocol is 'http:'
                cmd = "curl #{source} -o #{stageDestination}"
                cmd += " -s" # silent
                cmd += " -x #{options.proxy}" if options.proxy
                mecano.execute
                  ssh: options.ssh
                  cmd: cmd
                  log: options.log
                  stdout: options.stdout
                  stderr: options.stderr
                , (err, executed, stdout, stderr) ->
                  return next curl.error err if err
                  checksum()
              else if u.protocol is 'ftp:'
                return next new Error 'FTP download not supported over SSH'
              else
                options.ssh.sftp (err, sftp) ->
                  return next err if err
                  rs = sftp.createReadStream u.pathname
                  ws = rs.pipe fs.createWriteStream stageDestination
                  ws.on 'close', ->
                    # downloaded++ #unless err
                    checksum()
                  ws.on 'error', next
            else
              ws = fs.createWriteStream(stageDestination)
              if u.protocol is 'http:'
                options.url = source
                request(options).pipe(ws)
              else if u.protocol is 'ftp:'
                options.host ?= u.hostname
                options.port ?= u.port
                if u.auth
                  {user, pass} = u.auth.split ':'
                options.user ?= user
                options.pass ?= pass
                ftp = new Ftp options
                ftp.getGetSocket u.pathname, (err, rs) ->
                  return next err if err
                  rs.pipe ws
                  rs.resume()
              else
                rs = fs.createReadStream(u.pathname)
                rs.pipe ws
              ws.on 'close', () ->
                checksum()
              ws.on 'error', (err) ->
                # No test agains this but error in case 
                # of connection issue leave an empty file
                mecano.remove ws, (err) ->
                  next err
          checksum = ->
            return unstage() unless md5sum
            options.log? "Compare the downloaded file with the user-provided checksum"
            misc.file.hash options.ssh, stageDestination, 'md5', (err, hash) ->
              return unstage() if hash is md5sum
              # Download is invalid, cleaning up
              misc.file.remove options.ssh, stageDestination, (err) ->
                return next err if err
                next new Error "Invalid checksum, found \"#{hash}\" instead of \"#{md5sum}\""
          unstage = ->
            # Note about next line: ssh might be null with file, not very clear
            # misc.file.rename options.ssh, stageDestination, destination, (err) ->
            #   return next err if err
            #   downloaded++
            #   next()
            options.log? "Move the downloaded file"
            mecano.move
              ssh: options.ssh
              source: stageDestination
              destination: destination
              source_md5: md5sum
            , (err, moved) ->
              return next err if err
              downloaded++ if moved
              next()
          prepare()
        .on 'both', (err) ->
          finish err, downloaded

`exec` `execute([goptions], options, callback)`
-----------------------------------------------
Run a command locally or with ssh if `host` or `ssh` is provided.

`options`           Command options include:   
*   `cmd`           String, Object or array; Command to execute.   
*   `code`          Expected code(s) returned by the command, int or array of int, default to 0.  
*   `code_skipped`  Expected code(s) returned by the command if it has no effect, executed will not be incremented, int or array of int.   
*   `cwd`           Current working directory.   
*   `env`           Environment variables, default to `process.env`.   
*   `gid`           Unix group id.   
*   `log`           Function called with a log related messages.   
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   
*   `stdout`        Writable Stream in which commands output will be piped.   
*   `stderr`        Writable Stream in which commands error will be piped.   
*   `uid`           Unix user id.   

`callback`          Received parameters are:   
*   `err`           Error if any.   
*   `executed`      Number of executed commandes.   
*   `stdout`        Stdout value(s) unless `stdout` option is provided.   
*   `stderr`        Stderr value(s) unless `stderr` option is provided.   

    execute: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, created, stdout, stderr) ->
        callback err, created, stdout, stderr if callback
        result.end err, created
      isArray = Array.isArray options
      misc.options options, (err, options) ->
        return finish err if err
        executed = 0
        stdouts = []
        stderrs = []
        escape = (cmd) ->
          esccmd = ''
          for char in cmd
            if char is '$'
              esccmd += '\\'
            esccmd += char
          esccmd
        stds = if callback then callback.length > 2 else false
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, i, next) ->
          # Validate parameters
          options = { cmd: options } if typeof options is 'string'
          return next new Error "Missing cmd: #{options.cmd}" unless options.cmd?
          options.code ?= [0]
          options.code = [options.code] unless Array.isArray options.code
          options.code_skipped ?= []
          options.code_skipped = [options.code_skipped] unless Array.isArray options.code_skipped
          # Start real work
          cmd = () ->
            options.log? "Execute: #{options.cmd}"
            run = exec options
            stdout = stderr = []
            if options.stdout
              run.stdout.pipe options.stdout, end: false
            if stds
              run.stdout.on 'data', (data) ->
                stdout.push data
            if options.stderr
              run.stderr.pipe options.stderr, end: false
            if stds
              run.stderr.on 'data', (data) ->
                stderr.push data
            run.on "exit", (code) ->
              # Givent some time because the "exit" event is sometimes
              # called before the "stdout" "data" event when runing
              # `make test`
              setTimeout ->
                stdouts.push if stds then stdout.join('') else undefined
                stderrs.push if stds then stderr.join('') else undefined
                if options.stdout
                  run.stdout.unpipe options.stdout
                if options.stderr
                  run.stderr.unpipe options.stderr
                if options.code.indexOf(code) is -1 and options.code_skipped.indexOf(code) is -1 
                  err = new Error "Invalid exec code #{code}"
                  err.code = code
                  return next err
                executed++ if options.code_skipped.indexOf(code) is -1 
                next()
              , 1
          conditions.all options, next, cmd
        .on 'both', (err) ->
          stdouts = stdouts[0] unless isArray
          stderrs = stderrs[0] unless isArray
          finish err, executed, stdouts, stderrs
      result

`extract([goptions], options, callback)` 
----------------------------------------

Extract an archive. Multiple compression types are supported. Unless 
specified as an option, format is derived from the source extension. At the 
moment, supported extensions are '.tgz', '.tar.gz' and '.zip'.   

`options`           Command options include:   
*   `source`        Archive to decompress.   
*   `destination`   Default to the source parent directory.   
*   `format`        One of 'tgz' or 'zip'.   
*   `creates`       Ensure the given file is created or an error is send in the callback.   
*   `not_if_exists` Cancel extraction if file exists.   
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `extracted`     Number of extracted archives.   

    extract: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      misc.options options, (err, options) ->
        return callback err if err
        extracted = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Validate parameters
          return next new Error "Missing source: #{options.source}" unless options.source
          destination = options.destination ? path.dirname options.source
          # Deal with format option
          if options.format?
            format = options.format
          else
            if /\.(tar\.gz|tgz)$/.test options.source
              format = 'tgz'
            else if /\.zip$/.test options.source
              format = 'zip'
            else
              ext = path.extname options.source
              return next new Error "Unsupported extension, got #{JSON.stringify(ext)}"
          # Start real work
          extract = () ->
            cmd = null
            switch format
              when 'tgz' then cmd = "tar xzf #{options.source} -C #{destination}"
              when 'zip' then cmd = "unzip -u #{options.source} -d #{destination}"
            # exec cmd, (err, stdout, stderr) ->
            options.cmd = cmd
            exec options, (err, stdout, stderr) ->
              return next err if err
              creates()
          # Step for `creates`
          creates = () ->
            return success() unless options.creates?
            misc.file.exists options.ssh, options.creates, (err, exists) ->
              return next new Error "Failed to create '#{path.basename options.creates}'" unless exists
              success()
          # Final step
          success = () ->
            extracted++
            next()
          # Run conditions
          if typeof options.should_exist is 'undefined'
            options.should_exist = options.source
          conditions.all options, next, extract
        .on 'both', (err) ->
          callback err, extracted
  
`git([goptions], options, callback`
-----------------------------------

`options`           Command options include:   
*   `source`        Git source repository address.   
*   `destination`   Directory where to clone the repository.   
*   `revision`      Git revision, branch or tag.   
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   
*   `stdout`        Writable EventEmitter in which command output will be piped.   
*   `stderr`        Writable EventEmitter in which command error will be piped.   

    git: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      misc.options options, (err, options) ->
        return callback err if err
        updated = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Sanitize parameters
          options.revision ?= 'HEAD'
          rev = null
          # Start real work
          prepare = ->
            misc.file.exists options.ssh, options.destination, (err, exists) ->
              return next err if err
              return clone() unless exists
              # return next new Error "Destination not a directory, got #{options.destination}" unless stat.isDirectory()
              gitDir = "#{options.destination}/.git"
              misc.file.exists options.ssh, gitDir, (err, exists) ->
                return next new Error "Not a git repository" unless exists
                log()
          clone = ->
            mecano.exec
              ssh: options.ssh
              cmd: "git clone #{options.source} #{options.destination}"
              cwd: path.dirname options.destination
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, executed, stdout, stderr) ->
              return next err if err
              checkout()
          log = ->
            mecano.exec
              ssh: options.ssh
              cmd: "git log --pretty=format:'%H' -n 1"
              cwd: options.destination
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, executed, stdout, stderr) ->
              return next err if err
              current = stdout.trim()
              mecano.exec
                ssh: options.ssh
                cmd: "git rev-list --max-count=1 #{options.revision}"
                cwd: options.destination
                log: options.log
                stdout: options.stdout
                stderr: options.stderr
              , (err, executed, stdout, stderr) ->
                return next err if err
                if stdout.trim() isnt current
                then checkout()
                else next()
          checkout = ->
            mecano.exec
              ssh: options.ssh
              cmd: "git checkout #{options.revision}"
              cwd: options.destination
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err) ->
              return next err if err
              updated++
              next()
          conditions.all options, next, prepare
        .on 'both', (err) ->
          callback err, updated

`ini([goptions], options, callback`
-----------------------------------

Write an object as .ini file. Note, we are internally using the
[ini](https://github.com/isaacs/ini) module. However, there is 
a subtile difference. Any key provided with value of `undefined` 
or `null` will be disregarded. Within a `merge`, it get more prowerfull
and tricky: the original value will be kept if `undefined` is provided 
while the value will be removed if `null` is provided.

The `ini` function rely on the `write` function and accept all of its 
options. It introduces the `merge` option which instruct to read the
destination file if it exists and merge its parsed object with the one
provided in the `content` option.

`options`           Command options include:   
*   `append`        Append the content to the destination file. If destination does not exist, the file will be created. When used with the `match` and `replace` options, it will append the `replace` value at the end of the file if no match if found and if the value is a string.   
*   `backup`        Create a backup, append a provided string to the filename extension or a timestamp if value is not a string.   
*   `content`       Object to stringify.     
*   `destination`   File path where to write content to or a callback.   
*   `from`          Replace from after this marker, a string or a regular expression.   
*   `local_source`  Treat the source as local instead of remote, only apply with "ssh" option.   
*   `match`         Replace this marker, a string or a regular expression.   
*   `merge`         Read the destination if it exists and merge its content.   
*   `replace`       The content to be inserted, used conjointly with the from, to or match options.   
*   `source`        File path from where to extract the content, do not use conjointly with content.   
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.  
*   `parse`         User-defined function to parse the content from ini format, default to `require('ini').parse`, see 'misc.ini.parse_multi_brackets'.   
*   `stringify`     User-defined function to stringify the content to ini format, default to `require('ini').stringify`, see 'misc.ini.stringify_square_then_curly' for an example.   
*   `separator`     Default separator between keys and values, default to " : ".   
*   `to`            Replace to before this marker, a string or a regular expression.   
*   `clean`         Remove all the lines whithout a key and a value   

    ini: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      clean = (content, undefinedOnly) ->
        for k, v of content
          if v and typeof v is 'object'
            content[k] = clean v, undefinedOnly
            continue
          delete content[k] if typeof v is 'undefined'
          delete content[k] if not undefinedOnly and v is null
        content
      result = child mecano
      finish = (err, written) ->
        callback err, written if callback
        result.end err, written
      misc.options options, (err, options) ->
        return finish err if err
        written = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          {merge, destination, content, ssh} = options
          # Validate parameters
          return next new Error 'Missing content' unless content
          return next new Error 'Missing destination' unless destination
          # Start real work
          get = ->
            return write() unless merge
            misc.file.exists ssh, destination, (err, exists) ->
              return next err if err
              return write() unless exists
              misc.file.readFile ssh, destination, 'ascii', (err, c) ->
                return next err if err and err.code isnt 'ENOENT'
                content = clean content, true
                parse = options.parse or misc.ini.parse
                content = misc.merge parse(c, options), content
                write()
          write = ->
            clean content #if options.clean
            stringify = options.stringify or misc.ini.stringify
            options.content = stringify content, options
            mecano.write options, (err, w) ->
              written += w
              next err
          get()
        .on 'both', (err) ->
          finish err, written
      result

`krb5_ktadd([goptions], options, callback`
----------------------------------------------

Create a new Kerberos principal and an optionnal keytab.

`options`           Command options include:   
*   `kadmin_server` Address of the kadmin server; optional, use "kadmin.local" if missing.   
*   `kadmin_principal`  KAdmin principal name unless `kadmin.local` is used.   
*   `kadmin_password`   Password associated to the KAdmin principal.   
*   `principal`     Principal to be created.   
*   `password`      Password associated to this principal; required if no randkey is provided. 
*   `randkey`       Generate a random key; required if no password is provided.   
*   `keytab`        Path to the file storing key entries.   
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   
*   `log`           Function called with a log related messages.  
*   `stdout`        Writable Stream in which commands output will be piped.   
*   `stderr`        Writable Stream in which commands error will be piped.   

    krb5_ktadd: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      misc.options options, (err, options) ->
        return callback err if err
        executed = 0
        each(options)
        .parallel( goptions.parallel )
        .on 'item', (options, next) ->
          modified = false;
          do_get = ->
            return do_end() unless options.keytab
            mecano.execute
              cmd: "klist -k #{options.keytab}"
              ssh: options.ssh
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
              code_skipped: 1
            , (err, exists, stdout, stderr) ->
              return next err if err
              return do_ktadd() unless exists
              keytab = {}
              for line in stdout.split '\n'
                if match = /^\s*(\d+)\s*(.*)\s*$/.exec line
                  [_, kvno, principal] = match
                  keytab[principal] = kvno
              # Principal is not listed inside the keytab
              return do_ktadd() unless keytab[options.principal]?
              mecano.execute
                cmd: misc.kadmin options, "getprinc #{options.principal}"
                ssh: options.ssh
                log: options.log
                stdout: options.stdout
                stderr: options.stderr
              , (err, exists, stdout, stderr) ->
                return err if err
                return do_ktadd() unless -1 is stdout.indexOf 'does not exist'
                vno = null
                for line in stdout.split '\n'
                  if match = /Key: vno (\d+)/.exec line
                    [_, vno] = match
                    break
                return do_chown() if keytab[principal] is vno
                do_ktadd()
          do_ktadd = ->
            mecano.execute
              cmd: misc.kadmin options, "ktadd -k #{options.keytab} #{options.principal}"
              ssh: options.ssh
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, ktadded) ->
              return next err if err
              modified = true
              do_chown()
          do_chown = () ->
            return do_chmod() if not options.keytab or (not options.uid and not options.gid)
            mecano.chown
              ssh: options.ssh
              log: options.log
              destination: options.keytab
              uid: options.uid
              gid: options.gid
            , (err, chowned) ->
              return next err if err
              modified = chowned if chowned
              do_chmod()
          do_chmod = () ->
            return do_end() if not options.keytab or not options.mode
            mecano.chmod
              ssh: options.ssh
              log: options.log
              destination: options.keytab
              mode: options.mode
            , (err, chmoded) ->
              return next err if err
              modified = chmoded if chmoded
              do_end()
          do_end = ->
            executed++ if modified
            next()
          conditions.all options, next, do_get
        .on 'both', (err) ->
          callback err, executed

`krb5_principal([goptions], options, callback`
----------------------------------------------

Create a new Kerberos principal and an optionnal keytab.

`options`           Command options include:   
*   `kadmin_server` Address of the kadmin server; optional, use "kadmin.local" if missing.   
*   `kadmin_principal`  KAdmin principal name unless `kadmin.local` is used.   
*   `kadmin_password`   Password associated to the KAdmin principal.   
*   `principal`     Principal to be created.   
*   `password`      Password associated to this principal; required if no randkey is provided. 
*   `randkey`       Generate a random key; required if no password is provided.   
*   `keytab`        Path to the file storing key entries.   
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   
*   `log`           Function called with a log related messages.  
*   `stdout`        Writable Stream in which commands output will be piped.   
*   `stderr`        Writable Stream in which commands error will be piped.   

    krb5_addprinc: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      misc.options options, (err, options) ->
        return callback err if err
        executed = 0
        each(options)
        .parallel( goptions.parallel )
        .on 'item', (options, next) ->
          return next new Error 'Property principal is required' unless options.principal
          return next new Error 'Password or randkey missing' if not options.password and not options.randkey
          modified = false
          do_kadmin = ->
            cmd = misc.kadmin options, if options.password
            then "addprinc -pw #{options.password} #{options.principal}"
            else "addprinc -randkey #{options.principal}"
            mecano.execute
              cmd: cmd
              ssh: options.ssh
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, _, stdout) ->
              return next err if err
              modified = true if -1 is stdout.indexOf 'already exists'
              do_keytab()
          do_keytab = ->
            mecano.krb5_ktadd options, (err, ktadded) ->
              modified = true if ktadded
              do_end()
          do_end = ->
            executed++ if modified
            next()
          conditions.all options, next, do_kadmin
        .on 'both', (err) ->
          callback err, executed

`krb5_delprinc([goptions], options, callback`
----------------------------------------------

Create a new Kerberos principal and an optionnal keytab.

`options`           Command options include:   
*   `principal`     Principal to be created.   
*   `kadmin_server` Address of the kadmin server; optional, use "kadmin.local" if missing.   
*   `kadmin_principal`  KAdmin principal name unless `kadmin.local` is used.   
*   `kadmin_password`   Password associated to the KAdmin principal.   
*   `keytab`        Path to the file storing key entries.   
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   
*   `log`           Function called with a log related messages.  
*   `stdout`        Writable Stream in which commands output will be piped.   
*   `stderr`        Writable Stream in which commands error will be piped.   

    krb5_delprinc: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      misc.options options, (err, options) ->
        return callback err if err
        executed = 0
        each(options)
        .parallel( goptions.parallel )
        .on 'item', (options, next) ->
          return next new Error 'Property principal is required' unless options.principal
          modified = true
          do_delprinc = ->
            mecano.execute
              cmd: misc.kadmin options, "delprinc -force #{options.principal}"
              ssh: options.ssh
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, _, stdout) ->
              return next err if err
              modified = true if -1 is stdout.indexOf 'does not exist'
              do_keytab()
          do_keytab = ->
            return do_end() unless options.keytab
            mecano.remove
              ssh: options.ssh
              destination: options.keytab
            , (err, removed) ->
              return next err if err
              modified++ if removed
              do_end()
          do_end = ->
            executed++ if modified
            next()
          conditions.all options, next, do_delprinc
        .on 'both', (err) ->
          callback err, executed
  
`ldap_acl([goptions], options, callback`
----------------------------------------

`options`           Command options include:   
*   `to`            What to control access to as a string.   
*   `by`            Who to grant access to and the access to grant as an array (eg: `{..., by:["ssf=64 anonymous auth"]}`)   
*   `url`           Specify URI referring to the ldap server, alternative to providing an [ldapjs client] instance.  
*   `binddn`        Distinguished Name to bind to the LDAP directory, alternative to providing an [ldapjs client] instance.  
*   `passwd`        Password for simple authentication, alternative to providing an [ldapjs client] instance.   
*   `ldap`          Instance of an pldapjs client][ldapclt], alternative to providing the `url`, `binddn` and `passwd` connection properties.   
*   `unbind`        Close the ldap connection, default to false if connection is an [ldapjs client][ldapclt] instance.   
*   `name`          Distinguish name storing the "olcAccess" property, using the database adress (eg: "olcDatabase={2}bdb,cn=config").   
*   `overwrite`     Overwrite existing "olcAccess", default is to merge.   
*   `log`           Function called with a log related messages.   
*   `acl`           In case of multiple acls, regroup "before", "to" and "by" as an array

Resources:
http://www.openldap.org/doc/admin24/access-control.html

[ldapclt]: http://ldapjs.org/client.html

    ldap_acl: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, modified) ->
        callback err, modified if callback
        result.end err, modified
      misc.options options, (err, options) ->
        return finish err if err
        modified = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          options.acls ?= [{}]
          conditions.all options, next, ->
            updated = false
            each(options.acls)
            .parallel(false)
            .on 'item', (acl, next) ->
              acl.before ?= options.before
              acl.to ?= options.to
              acl.by ?= options.by
              client = null
              acl.to = acl.to.trim()
              for b, i in acl.by
                acl.by[i] = b.trim()
              connect = ->
                if options.ldap instanceof ldap_client
                  client = options.ldap
                  return search()
                options.log? 'Open and bind connection'
                client = ldap.createClient url: options.url
                client.bind options.binddn, options.passwd, (err) ->
                  return end err if err
                  search()
              search = ->
                  options.log? 'Search attribute olcAccess'
                  client.search options.name,
                    scope: 'base'
                    attributes: ['olcAccess']
                  , (err, search) ->
                    return unbind err if err
                    olcAccess = null
                    search.on 'searchEntry', (entry) ->
                      options.log? "Found #{JSON.stringify entry.object}"
                      # typeof olcAccess may be undefined, array or string
                      olcAccess = entry.object.olcAccess or []
                      olcAccess = [olcAccess] unless Array.isArray olcAccess
                    search.on 'end', ->
                      options.log? "Attribute olcAccess was #{JSON.stringify olcAccess}"
                      parse olcAccess
              parse = (_olcAccess) ->
                olcAccess = []
                for access, i in _olcAccess
                  to = ''
                  bys = []
                  buftype = 0 # 0: start, 1: to, 2:by
                  buf = ''
                  for c, i in access
                    buf += c
                    if buftype is 0
                      if /to$/.test buf
                        buf = ''
                        buftype = 1
                    if buftype is 1
                      if matches = /^(.*)by$/.exec buf
                        to = matches[1].trim()
                        buf = ''
                        buftype = 2
                    if buftype is 2
                      if matches = /^(.*)by$/.exec buf
                        bys.push matches[1].trim()
                        buf = ''
                      else if i+1 is access.length
                        bys.push buf.trim()
                  olcAccess.push
                    to: to
                    by: bys
                diff olcAccess
              diff = (olcAccess) ->
                toAlreadyExist = false
                for access, i in olcAccess
                  continue unless acl.to is access.to
                  toAlreadyExist = true
                  fby = unless options.overwrite then access.by else []
                  for oby in acl.by
                    found = false
                    for aby in access.by
                      if oby is aby
                        found = true
                        break
                    unless found
                      updated = true
                      fby.push oby 
                  olcAccess[i].by = fby
                unless toAlreadyExist
                  updated = true
                  # place before
                  if acl.before
                    found = null
                    for access, i in olcAccess
                      found = i if access.to is acl.before
                    # throw new Error 'Before does not match any "to" rule' unless found?
                    olcAccess.splice found-1, 0, to: acl.to, by: acl.by
                  # place after
                  else if acl.after
                    found = false
                    for access, i in olcAccess
                      found = i if access.to is options.after
                    # throw new Error 'After does not match any "to" rule'
                    olcAccess.splice found, 0, to: acl.to, by: acl.by
                  # append
                  else
                    olcAccess.push to: acl.to, by: acl.by
                if updated then stringify(olcAccess) else unbind()
              stringify = (olcAccess) ->
                for access, i in olcAccess
                  value = "{#{i}}to #{access.to}"
                  for bie in access.by
                    value += " by #{bie}"
                  olcAccess[i] = value
                save olcAccess
              save = (olcAccess) ->
                change = new ldap.Change 
                  operation: 'replace'
                  modification: olcAccess: olcAccess
                client.modify options.name, change, (err) ->
                  unbind err
              unbind = (err) ->
                options.log? 'Unbind connection'
                # return end err unless options.unbind and options.ldap instanceof ldap_client
                return end err if options.ldap instanceof ldap_client and not options.unbind
                client.unbind (e) ->
                  return next e if e
                  end err
              end = (err) ->
                next err
              connect()
            .on 'both', (err) ->
              modified += 1 if updated and not err
              # finish err, modified
              next err
        .on 'both', (err) ->
          finish err, modified
      result

`ldap_index([goptions], options, callback`
------------------------------------------

`options`           Command options include:   
*   `indexes`       Object with keys mapping to indexed attributes and values mapping to indices ("pres", "approx", "eq", "sub" and 'special').   
*   `url`           Specify URI referring to the ldap server, alternative to providing an [ldapjs client] instance.  
*   `binddn`        Distinguished Name to bind to the LDAP directory, alternative to providing an [ldapjs client] instance.  
*   `passwd`        Password for simple authentication, alternative to providing an [ldapjs client] instance.   
*   `ldap`          Instance of an pldapjs client][ldapclt], alternative to providing the `url`, `binddn` and `passwd` connection properties.   
*   `unbind`        Close the ldap connection, default to false if connection is an [ldapjs client][ldapclt] instance.   
*   `name`          Distinguish name storing the "olcAccess" property, using the database adress (eg: "olcDatabase={2}bdb,cn=config").   
*   `overwrite`     Overwrite existing "olcAccess", default is to merge.   

Resources:   
-   http://www.zytrax.com/books/ldap/apa/indeces.html

    ldap_index: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, created) ->
        callback err, created if callback
        result.end err, created
      misc.options options, (err, options) ->
        return finish err if err
        modified = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          client = null
          updated = false
          connect = ->
            if options.ldap instanceof ldap_client
              client = options.ldap
              return get()
            # Open and bind connection
            client = ldap.createClient url: options.url
            client.bind options.binddn, options.passwd, (err) ->
              return end err if err
              get()
          get = ->
            client.search 'olcDatabase={2}bdb,cn=config', 
                scope: 'base'
                attributes: ['olcDbIndex']
            , (err, search) ->
              olcDbIndex = null
              search.on 'searchEntry', (entry) ->
                olcDbIndex = entry.object.olcDbIndex
              search.on 'end', ->
                parse olcDbIndex
          parse = (arIndex) ->
            indexes = {}
            for index in arIndex
              [k,v] = index.split ' '
              indexes[k] = v
            diff indexes
          diff = (orgp) ->
            unless options.overwrite
              newp = misc.merge {}, orgp, options.indexes
            else
              newp = options.indexes
            okl = Object.keys(orgp).sort()
            nkl = Object.keys(newp).sort()
            for i in [0...Math.min(okl.length, nkl.length)]
              if i is okl.length or i is nkl.length or okl[i] isnt nkl[i] or orgp[okl[i]] isnt newp[nkl[i]]
                updated = true
                break
            if updated then stringifiy newp else unbind()
          stringifiy = (perms) ->
            indexes = []
            for k, v of perms
              indexes.push "#{k} #{v}"
            replace indexes
          replace = (indexes) ->
            change = new ldap.Change
              operation: 'replace'
              modification: 
                olcDbIndex: indexes
            client.modify options.name, change, (err) ->
              unbind err
          unbind = (err) ->
            return end err if options.ldap instanceof ldap_client and not options.unbind
            client.unbind (e) ->
              return next e if e
              end err
          end = (err) ->
            modified += 1 if updated and not err
            next err
          conditions.all options, next, connect
        .on 'both', (err) ->
          finish err, modified
      result

`ldap_schema([goptions], options, callback)`
--------------------------------------------

Register a new ldap schema.

`options`           Command options include:   
*   `url`           Specify URI referring to the ldap server, alternative to providing an [ldapjs client] instance.  
*   `binddn`        Distinguished Name to bind to the LDAP directory, alternative to providing an [ldapjs client] instance.  
*   `passwd`        Password for simple authentication, alternative to providing an [ldapjs client] instance.   
*   `name`          Common name of the schema.   
*   `schema`        Path to the schema definition.   
*   `overwrite`     Overwrite existing "olcAccess", default is to merge.   
*   `log`           Function called with a log related messages.   

    ldap_schema: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, created) ->
        callback err, created if callback
        result.end err, created
      misc.options options, (err, options) ->
        return finish err if err
        modified = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          return next new Error "Missing name" unless options.name
          return next new Error "Missing schema" unless options.schema
          options.schema = options.schema.trim()
          tempdir = options.tempdir or "/tmp/mecano_ldap_schema_#{Date.now()}"
          schema = "#{tempdir}/#{options.name}.schema"
          conf = "#{tempdir}/schema.conf"
          ldif = "#{tempdir}/ldif"
          registered = ->
            binddn = if options.binddn then "-D #{options.binddn}" else ''
            passwd = if options.passwd then "-w #{options.passwd}" else ''
            cmd = "ldapsearch #{binddn} #{passwd} -b \"cn=schema,cn=config\" | grep -E cn=\\{[0-9]+\\}#{options.name},cn=schema,cn=config"
            options.log? "Check if schema is registered: #{cmd}"
            mecano.execute
              cmd: cmd
              code: 0
              code_skipped: 1
              ssh: options.ssh
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, registered, stdout) ->
              return next err if err
              return next() if registered
              dir()
          dir = ->
            options.log? 'Create ldif directory'
            mecano.mkdir
              destination: ldif
              ssh: options.ssh
            , (err, executed) ->
              return next err if err
              write()
          write = ->
            options.log? 'Copy schema'
            mecano.copy
              source: options.schema
              destination: schema
              ssh: options.ssh
            , (err, copied) ->
              return next err if err
              options.log? 'Prepare configuration'
              mecano.write
                content: "include #{schema}"
                destination: conf
                ssh: options.ssh
              , (err) ->
                return next err if err
                generate()
          generate = ->
            options.log? 'Generate configuration'
            mecano.execute
              cmd: "slaptest -f #{conf} -F #{ldif}"
              ssh: options.ssh
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, executed) ->
              return next err if err
              rename()
          rename = ->
            options.log? 'Rename configuration'
            mecano.move
              source: "#{ldif}/cn=config/cn=schema/cn={0}#{options.name}.ldif"
              destination: "#{ldif}/cn=config/cn=schema/cn=#{options.name}.ldif"
              force: true
              ssh: options.ssh
            , (err, moved) ->
              return next err if err
              return new Error 'No generated schema' unless moved
              configure()
          configure = ->
            options.log? 'Prepare ldif'
            mecano.write
              destination: "#{ldif}/cn=config/cn=schema/cn=#{options.name}.ldif"
              write: [
                match: /^dn: cn.*$/mg
                replace: "dn: cn=#{options.name},cn=schema,cn=config"
              ,
                match: /^cn: {\d+}(.*)$/mg
                replace: 'cn: $1'
              ,
                match: /^structuralObjectClass.*/mg
                replace: ''
              ,
                match: /^entryUUID.*/mg
                replace: ''
              ,
                match: /^creatorsName.*/mg
                replace: ''
              ,
                match: /^createTimestamp.*/mg
                replace: ''
              ,
                match: /^entryCSN.*/mg
                replace: ''
              ,
                match: /^modifiersName.*/mg
                replace: ''
              ,
                match: /^modifyTimestamp.*/mg
                replace: ''
              ]
              ssh: options.ssh
            , (err, written) ->
              return next err if err
              register()
          register = ->
            uri = if options.uri then"-L #{options.uri}" else ''
            binddn = if options.binddn then "-D #{options.binddn}" else ''
            passwd = if options.passwd then "-w #{options.passwd}" else ''
            cmd = "ldapadd #{uri} #{binddn} #{passwd} -f #{ldif}/cn=config/cn=schema/cn=#{options.name}.ldif"
            options.log? "Add schema: #{cmd}"
            mecano.execute
              cmd: cmd
              ssh: options.ssh
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, executed) ->
              return next err if err
              modified++
              clean()
          clean = ->
            options.log? 'Clean up'
            mecano.remove
              destination: tempdir
              ssh: options.ssh
            , (err, removed) ->
              next err
          conditions.all options, next, registered
        .on 'both', (err) ->
          finish err, modified
      result

`ln` `link([goptions], options, callback)`
------------------------------------------

Create a symbolic link and it's parent directories if they don't yet
exist.   

`options`           Command options include:   
*   `source`        Referenced file to be linked.   
*   `destination`   Symbolic link to be created.   
*   `exec`          Create an executable file with an `exec` command.   
*   `mode`          Default to 0755.   

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `linked`        Number of created links.   

Simple usage:   
```coffee
mecano.link
  source: __dirname
  destination: destination
, (err, linked) ->
  console.info linked
```

    link: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, created) ->
        callback err, created if callback
        result.end err, created
      misc.options options, (err, options) ->
        return finish err if err
        linked = 0
        sym_exists = (options, callback) ->
          misc.file.exists options.ssh, options.destination, (err, exists) ->
            return callback null, false unless exists
            misc.file.readlink options.ssh, options.destination, (err, resolvedPath) ->
              return callback err if err
              return callback null, true if resolvedPath is options.source
              misc.file.unlink options.ssh, options.destination, (err) ->
                return callback err if err
                callback null, false
        sym_create = (options, callback) ->
          misc.file.symlink options.ssh, options.source, options.destination, (err) ->
            return callback err if err
            linked++
            callback()
        exec_exists = (options, callback) ->
          misc.file.exists options.ssh, options.destination, (err, exists) ->
            return callback null, false unless exists
            misc.file.readFile options.ssh, options.destination, 'utf8', (err, content) ->
              return callback err if err
              exec_cmd = /exec (.*) \$@/.exec(content)[1]
              callback null, exec_cmd and exec_cmd is options.source
        exec_create = (options, callback) ->
          content = """
          #!/bin/bash
          exec #{options.source} $@
          """
          misc.file.writeFile options.ssh, options.destination, content, (err) ->
            return callback err if err
            misc.file.chmod options.ssh, options.destination, options.mode, (err) ->
              return callback err if err
              linked++
              callback()
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # return next new Error 'SSH not yet supported' if options.ssh
          return next new Error "Missing source, got #{JSON.stringify(options.source)}" unless options.source
          return next new Error "Missing destination, got #{JSON.stringify(options.destination)}" unless options.destination
          options.mode ?= 0o0755
          do_mkdir = ->
            mecano.mkdir
              ssh: options.ssh
              destination: path.dirname options.destination
            , (err, created) ->
              # It is possible to have collision if to symlink
              # have the same parent directory
              return callback err if err and err.code isnt 'EEXIST'
              do_dispatch()
          do_dispatch = ->
            if options.exec
              exec_exists options, (err, exists) ->
                return next() if exists
                exec_create options, next
            else
              sym_exists options, (err, exists) ->
                return next() if exists
                sym_create options, next
          do_mkdir()
        .on 'both', (err) ->
          callback err, linked
      result

`mkdir([goptions], options, callback)`
--------------------------------------

Recursively create a directory. The behavior is similar to the Unix command `mkdir -p`. 
It supports an alternative syntax where options is simply the path of the directory
to create.

`options`           Command options include:   
*   `cwd`           Current working directory for relative paths.   
*   `uid`           Unix user id.   
*   `gid`           Unix group id.  
*   `mode`          Default to 0755.  
*   `directory`     Path or array of paths.
*   `destination`   Alias for `directory`.
*   `exclude`       Regular expression.   
*   `source`        Alias for `directory`.   

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `created`       Number of created directories

Simple usage:
```coffee
mecano.mkdir './some/dir', (err, created) ->
  console.info err?.message ? created
```

Advance usage:
```coffee
mecano.mkdir 
  ssh: options.ssh
  destination: './some/dir'
  uid: 'me'
  gid: 'my_group'
  mode: 0o0777 or '777'
```

    mkdir: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, created) ->
        callback err, created if callback
        result.end err, created
      misc.options options, (err, options) ->
        return finish err if err
        created = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Validate parameters
          options = { directory: options } if typeof options is 'string'
          options.directory ?= options.source
          options.directory ?= options.destination
          return next new Error 'Missing directory option' unless options.directory?
          options.log? "Create directory #{options.directory}"
          cwd = options.cwd ? process.cwd()
          options.directory = [options.directory] unless Array.isArray options.directory
          conditions.all options, next, ->
            mode = options.mode or 0o0755
            each(options.directory)
            .on 'item', (directory, next) ->
              # first, we need to find which directory need to be created
              do_stats = ->
                end = false
                dirs = []
                directory = path.resolve cwd, directory # path.resolve also normalize
                # Create directory and its parent directories
                directories = directory.split('/')
                directories.shift() # first element is empty with absolute path
                directories = for i in [0...directories.length]
                  '/' + directories.slice(0, directories.length - i).join '/'
                each(directories)
                .on 'item', (directory, i, next) ->
                  return next() if end
                  misc.file.stat options.ssh, directory, (err, stat) ->
                    if err?.code is 'ENOENT' # if the directory is not yet created
                      directory.stat = stat
                      dirs.push directory
                      if i is directories.length - 1
                      then return do_create(dirs)
                      else return next()
                    if stat?.isDirectory()
                      end = true
                      return  if i is 0 then do_update(stat) else do_create(dirs)
                    if err
                      return next err
                    else # a file or symlink exists at this location
                      return next new Error 'Not a directory: #{JSON.encode(directory)}'
                .on 'both', (err) ->
                  return next err if err
              do_create = (directories) ->
                each(directories.reverse())
                .on 'item', (directory, next) ->
                  # Directory name contains variables
                  # eg /\${/ on './var/cache/${user}' creates './var/cache/'
                  if options.exclude? and options.exclude instanceof RegExp
                    return next() if options.exclude.test path.basename directory
                  misc.file.mkdir options.ssh, directory, options, (err) ->
                    return next err if err
                    modified = true
                    next()
                .on 'both', (err) ->
                  created++
                  next err
              do_update = (stat) ->
                modified = false
                do_chown = ->
                  # todo, change ownership
                  mecano.chown
                    ssh: options.ssh
                    destination: directory
                    uid: options.uid
                    gid: options.gid
                  , (err, owned) ->
                    modified = true if owned
                    do_chmod()
                do_chmod = ->
                  return do_end() unless mode
                  # todo: fix this one
                  return do_end() if misc.file.cmpmod stat.mode, mode
                  misc.file.chmod options.ssh, directory, mode, (err) ->
                    modified = true
                    do_end()
                do_end = ->
                  created++ if modified
                  next()
                do_chown()
              do_stats()
            .on 'both', (err) ->
              next err
        .on 'both', (err) ->
          finish err, created
      result

`mv` `move([goptions], options, callback)`
------------------------------------------

Move files and directories. It is ok to overwrite the destination file if it exists, 
in which case the source file will no longer exists.    

`options`               Command options include:   
*   `destination`       Final name of the moved resource.   
*   `force`             Force the replacement of the file without checksum verification, speed up the action and disable the `moved` indicator in the callback.   
*   `source`            File or directory to move.   
*   `destination_md5`   Destination md5 checkum if known, otherwise computed if destination exists
*   `source_md5`        Source md5 checkum if known, otherwise computed

`callback`              Received parameters are:   
*   `err`               Error object if any.   
*   `moved`             Number of moved resources.

Example
```coffee
mecano.mv
  source: __dirname
  desination: '/temp/my_dir'
, (err, moved) ->
  console.info "#{moved} dir moved"
```

    move: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      misc.options options, (err, options) ->
        return callback err if err
        moved = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Start real work
          exists = ->
            misc.file.stat options.ssh, options.destination, (err, stat) ->
              return move() if err?.code is 'ENOENT'
              return next err if err
              if options.force
              then remove_dest()
              else srchash()
          srchash = ->
            return dsthash() if options.source_md5
            misc.file.hash options.ssh, options.source, 'md5', (err, hash) ->
              return next err if err
              options.source_md5 = hash
              dsthash()
          dsthash = ->
            return chkhash() if options.destination_md5
            misc.file.hash options.ssh, options.destination, 'md5', (err, hash) ->
              return next err if err
              options.destination_md5 = hash
              chkhash()
          chkhash = ->
            if options.source_md5 is options.destination_md5
            then remove_src()
            else remove_dest()
          remove_dest = ->
            options.log? "Remove #{options.destination}"
            mecano.remove
              ssh: options.ssh
              destination: options.destination
            , (err, removed) ->
              return next err if err
              move()
          move = ->
            options.log? "Rename #{options.source} to #{options.destination}"
            misc.file.rename options.ssh, options.source, options.destination, (err) ->
              return next err if err
              moved++
              next()
          remove_src = ->
            options.log? "Remove #{options.source}"
            mecano.remove
              ssh: options.ssh
              destination: options.source
            , (err, removed) ->
              next err
          conditions.all options, next, exists
        .on 'both', (err) ->
          callback err, moved

`rm` `remove([goptions], options, callback)`
--------------------------------------------

Recursively remove files, directories and links. Internally, the function 
use the [rimraf](https://github.com/isaacs/rimraf) library.

`options`           Command options include:   
*   `source`        File, directory or pattern.  
*   `destination`   Alias for "source". 

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `removed`       Number of removed sources.   

Basic example
```coffee
mecano.rm './some/dir', (err, removed) ->
  console.info "#{removed} dir removed"
```

Removing a directory unless a given file exists
```coffee
mecano.rm
  source: './some/dir'
  not_if_exists: './some/file'
, (err, removed) ->
  console.info "#{removed} dir removed"
```

Removing multiple files and directories
```coffee
mecano.rm [
  { source: './some/dir', not_if_exists: './some/file' }
  './some/file'
], (err, removed) ->
  console.info "#{removed} dirs removed"
```

    remove: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, removed) ->
        callback err, removed if callback
        result.end err, removed
      misc.options options, (err, options) ->
        return finish err if err
        removed = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Validate parameters
          options = source: options if typeof options is 'string'
          options.source ?= options.destination
          return next new Error "Missing source" unless options.source?
          # Start real work
          remove = ->
            if options.ssh
              options.log? "Remove #{options.source}"
              misc.file.exists options.ssh, options.source, (err, exists) ->
                return next err if err
                removed++ if exists
                misc.file.remove options.ssh, options.source, next
            else
              each()
              .files(options.source)
              .on 'item', (file, next) ->
                removed++
                options.log? "Remove #{file}"
                misc.file.remove options.ssh, file, next
              .on 'error', (err) ->
                next err
              .on 'end', ->
                next()
          conditions.all options, next, remove
        .on 'both', (err) ->
          finish err, removed
      result

`render([goptions], options, callback)`
---------------------------------------

Render a template file At the moment, only the 
[ECO](http://github.com/sstephenson/eco) templating engine is integrated.   

`options`           Command options include:   
*   `engine`        Template engine to use, default to "eco"   
*   `content`       Templated content, bypassed if source is provided.   
*   `source`        File path where to extract content from.   
*   `destination`   File path where to write content to or a callback.   
*   `context`       Map of key values to inject into the template.   
*   `local_source`  Treat the source as local instead of remote, only apply with "ssh" option.   
*   `uid`           File user name or user id
*   `gid`           File group name or group id
*   `mode`          File mode (permission and sticky bits), default to `0666`, in the for of `{mode: 0o744}` or `{mode: "744"}`

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `rendered`      Number of rendered files.   

If destination is a callback, it will be called multiple times with the   
generated content as its first argument.

    render: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      misc.options options, (err, options) ->
        return callback err if err
        rendered = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Validate parameters
          return next new Error 'Missing source or content' unless options.source or options.content
          return next new Error 'Missing destination' unless options.destination
          # Start real work
          readSource = ->
            return writeContent() unless options.source
            ssh = if options.local_source then null else options.ssh
            misc.file.exists ssh, options.source, (err, exists) ->
              return next new Error "Invalid source, got #{JSON.stringify(options.source)}" unless exists
              misc.file.readFile ssh, options.source, 'utf8', (err, content) ->
                return next err if err
                options.content = content
                writeContent()
          writeContent = ->
            options.source = null
            mecano.write options, (err, written) ->
              return next err if err
              rendered++ if written
              next()
          conditions.all options, next, readSource
        .on 'both', (err) ->
          callback err, rendered

`service([goptions], options, callback)`
----------------------------------------

Install a service. For now, only yum over SSH.   

`options`           Command options include:   
*   `name`          Package name.   
*   `startup`       Run service daemon on startup. If true, startup will be set to '2345', use an empty string to not define any run level.   
*   `yum_name`      Name used by the yum utility, default to "name".   
*   `chk_name`      Name used by the chkconfig utility, default to "srv_name" and "name".   
*   `srv_name`      Name used by the service utility, default to "name".   
*   `cache`         Run entirely from system cache, run install and update checks offline.   
#   `start`         Ensure the service is started, a boolean.   
#   `stop`          Ensure the service is stopped, a boolean.   
*   `action`        Execute the service with the provided action argument.
*   `stdout`        Writable Stream in which commands output will be piped.   
*   `stderr`        Writable Stream in which commands error will be piped.   
*   `installed`     Cache a list of installed services. If an object, the service will be installed if a key of the same name exists; if anything else (default), no caching will take place.   
*   `updates`       Cache a list of outdated services. If an object, the service will be updated if a key of the same name exists; If true, the option will be converted to an object with all the outdated service names as keys; if anything else (default), no caching will take place.   

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `modified`      Number of action taken (installed, updated, started or stoped).   
*   `installed`     List of installed services.   
*   `updates`       List of services to update.   

    service: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments, parallel: 1
      installed = updates = null
      misc.options options, (err, options) ->
        return callback err if err
        serviced = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          # Validate parameters
          return next new Error 'Missing service name' unless options.name
          return next new Error 'Restricted to Yum over SSH' unless options.ssh
          # return next new Error 'Invalid configuration, start conflict with stop' if options.start? and options.start is options.stop
          pkgname = options.yum_name or options.name
          chkname = options.chk_name or options.srv_name or options.name
          srvname = options.srv_name or options.name
          if options.startup? and typeof options.startup isnt 'string'
              options.startup = if options.startup then '2345' else ''
          modified = false
          installed ?= options.installed
          updates ?= options.updates
          # Start real work
          chkinstalled = ->
            cache = ->
              options.log? "List installed packages"
              c = if options.cache then '-C' else ''
              mecano.execute
                ssh: options.ssh
                # cmd: "yum #{c} list installed"
                cmd: "yum -C list installed"
                # cmd: "rpm -qa"
                code_skipped: 1
                log: options.log
                stdout: options.stdout
                stderr: options.stderr
              , (err, executed, stdout) ->
                return next err if err
                stdout = stdout.split '\n'
                start = false
                installed = []
                for pkg in stdout
                  start = true if pkg.trim() is 'Installed Packages'
                  continue unless start
                  installed.push pkg[1] if pkg = /^([^\. ]+?)\./.exec pkg
                decide()
            decide = ->
              if installed.indexOf(pkgname) isnt -1 then chkupdates() else install()
            if installed then decide() else cache()
            # mecano.execute
            #   ssh: options.ssh
            #   cmd: "yum list installed | grep ^#{pkgname}\\\\."
            #   code_skipped: 1
            #   stdout: options.stdout
            #   stderr: options.stderr
            # , (err, installed) ->
            #   return next err if err
            #   if installed then updates() else install()
          chkupdates = ->
            cache = ->
              options.log? "List available updates"
              c = if options.cache then '-C' else ''
              mecano.execute
                ssh: options.ssh
                cmd: "yum #{c} list updates"
                code_skipped: 1
                log: options.log
                stdout: options.stdout
                stderr: options.stderr
              , (err, executed, stdout) ->
                return next err if err
                stdout = stdout.split '\n'
                start = false
                updates = []
                for pkg in stdout
                  start = true if pkg.trim() is 'Updated Packages'
                  continue unless start
                  updates.push pkg[1] if pkg = /^([^\. ]+?)\./.exec pkg
                decide()
            decide = ->
              if updates.indexOf(pkgname) isnt -1 then install() else startuped()
            if updates then decide() else cache()
          install = ->
            options.log? "Install the package #{pkgname}"
            mecano.execute
              ssh: options.ssh
              cmd: "yum install -y #{pkgname}"
              code_skipped: 1
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, succeed) ->
              return next err if err
              installedIndex = installed.indexOf pkgname
              installed.push pkgname if installedIndex is -1
              if updates
                updatesIndex = updates.indexOf pkgname
                updates.splice updatesIndex, 1 unless updatesIndex is -1
              # Those 2 lines seems all wrong
              return next new Error "No package #{pkgname} available." unless succeed
              modified = true if installedIndex isnt -1
              startuped()
          startuped = ->
            return started() unless options.startup?
            options.log? "List startup services"
            mecano.execute
              ssh: options.ssh
              cmd: "chkconfig --list #{chkname}"
              code_skipped: 1
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, registered, stdout, stderr) ->
              return next err if err
              # Invalid service name return code is 0 and message in stderr start by error
              return next new Error "Invalid chkconfig name #{chkname}" if /^error/.test stderr
              current_startup = ''
              if registered
                for c in stdout.split(' ').pop().trim().split '\t'
                  [level, status] = c.split ':'
                  current_startup += level if ['on', 'marche'].indexOf(status) > -1
              return started() if options.startup is current_startup
              modified = true
              if options.startup?
              then startup_add()
              else startup_del()
          startup_add = ->
            options.log? "Add startup service"
            startup_on = startup_off = ''
            for i in [0...6]
              if options.startup.indexOf(i) isnt -1
              then startup_on += i
              else startup_off += i
            cmd = "chkconfig --add #{chkname};"
            cmd += "chkconfig --level #{startup_on} #{chkname} on;" if startup_on
            cmd += "chkconfig --level #{startup_off} #{chkname} off;" if startup_off
            mecano.execute
              ssh: options.ssh
              cmd: cmd
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err) ->
              return next err if err
              started()
          startup_del = ->
            options.log? "Remove startup service"
            mecano.execute
              ssh: options.ssh
              cmd: "chkconfig --del #{chkname}"
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err) ->
              return next err if err
              started()
          started = ->
            return action() if options.action isnt 'start' and options.action isnt 'stop'
            options.log? "Check if service is started"
            mecano.execute
              ssh: options.ssh
              cmd: "service #{srvname} status"
              code_skipped: 3
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, started) ->
              return next err if err
              if started
                return action() unless options.action is 'start'
              else
                return action() unless options.action is 'stop'
              finish() 
          action = ->
            return finish() unless options.action
            options.log? "Start/stop the service"
            mecano.execute
              ssh: options.ssh
              cmd: "service #{srvname} #{options.action}"
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, executed) ->
              return next err if err
              modified = true
              finish()
          finish = ->
            serviced++ if modified
            next()
          conditions.all options, next, chkinstalled
        .on 'both', (err) ->
          callback err, serviced, installed, updates

`touch([goptions], options, callback)`
--------------------------------------

Create a empty file if it does not yet exists.

    touch: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, modified) ->
        callback err, modified if callback
        result.end err, modified
      misc.options options, (err, options) ->
        return finish err if err
        modified = 0
        each( options )
        .on 'item', (options, next) ->
          # Validate parameters
          {ssh, destination, mode} = options
          return next new Error "Missing destination: #{destination}" unless destination
          misc.file.exists ssh, destination, (err, exists) ->
            return next err if err
            return next if exists
            options.source = null
            options.content = ''
            mecano.write options, (err, written) ->
              return next err if err
              modified++
              next()
        .on 'both', (err) ->
          finish err, modified

`upload([goptions], options, callback)`
---------------------------------------

Upload a file to a remote location. Options are 
identical to the "write" function with the addition of 
the "binary" option.

`options`           Command options include:   
*   `binary`        Fast upload implementation, discard all the other option and use its own stream based implementation.   
*   `from`          Replace from after this marker, a string or a regular expression.   
*   `to`            Replace to before this marker, a string or a regular expression.   
*   `match`         Replace this marker, a string or a regular expression.   
*   `replace`       The content to be inserted, used conjointly with the from, to or match options.   
*   `content`       Text to be written.   
*   `source`        File path from where to extract the content, do not use conjointly with content.   
*   `destination`   File path where to write content to.   
*   `backup`        Create a backup, append a provided string to the filename extension or a timestamp if value is not a string.   
*   `md5`           Validate uploaded file with md5 checksum (only for binary upload for now).
*   `sha1`          Validate uploaded file with sha1 checksum (only for binary upload for now).

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `rendered`      Number of rendered files. 

    upload: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, uploaded) ->
        callback err, uploaded if callback
        result.end err, uploaded
      misc.options options, (err, options) ->
        return finish err if err
        uploaded = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          conditions.all options, next, ->
            # Start real work
            if options.binary
              get_checksum = (path, digest, callback) ->
                mecano.execute
                  ssh: options.ssh
                  cmd: "openssl #{digest} #{path}"
                  log: options.log
                  stdout: options.stdout
                  stderr: options.stderr
                , (err, executed, stdout, stderr) ->
                  return callback err if err
                  callback null, /[ ](.*)$/.exec(stdout.trim())[1]
              do_exists = ->
                options.log? "Check if #{options.destination} exists remotely"
                misc.file.exists options.ssh, options.destination, (err, exists) ->
                  return next err if err
                  return do_upload() unless exists
                  return do_upload() unless options.md5 or options.sha1
                  options.log? "Make sure destination checksum is valid"
                  switch
                    when options.md5? then get_checksum options.destination, 'md5', (err, md5) ->
                      return next err if err
                      if md5 is options.md5
                      then next()
                      else do_upload()
                    when options.sha1? then get_checksum options.destination, 'sha1', (err, sha1) ->
                      return next err if err
                      if sha1 is options.sha1
                      then next()
                      else do_upload()
              do_upload = ->
                options.log? "Upload #{options.source}"
                options.ssh.sftp (err, sftp) ->
                  from = fs.createReadStream options.source#, encoding: 'binary'
                  to = sftp.createWriteStream options.destination#, encoding: 'binary'
                  l = 0
                  from.pipe to
                  from.on 'error', next
                  to.on 'error', next
                  to.on 'close', ->
                    uploaded++
                    do_md5()
              do_md5 = ->
                return do_sha1() unless options.md5
                options.log? "Check md5 for '#{options.destination}'"
                get_checksum options.destination, 'md5', (err, md5) ->
                  return next new Error "Invalid md5 checksum" if md5 isnt options.md5
                  do_sha1()
              do_sha1 = ->
                return do_end() unless options.sha1
                options.log? "Check sha1 for '#{options.destination}'"
                get_checksum options.destination, 'sha1', (err, sha1) ->
                  return next new Error "Invalid sha1 checksum" if sha1 isnt options.sha1
                  do_end()
              do_end = ->
                options.log? "Upload succeed in #{options.destination}"
                next()
              return do_exists()
            options = misc.merge options, local_source: true
            mecano.write options, (err, written) ->
              uploaded++ if written is 1
              next err
        .on 'both', (err) ->
          finish err, uploaded
      result

`write([goptions], options, callback)`
--------------------------------------

Write a file or a portion of an existing file.

`options`           Command options include:   
*   `from`          Replace from after this marker, a string or a regular expression.   
*   `local_source`  Treat the source as local instead of remote, only apply with "ssh" option.   
*   `to`            Replace to before this marker, a string or a regular expression.   
*   `match`         Replace this marker, a string or a regular expression.   
*   `replace`       The content to be inserted, used conjointly with the from, to or match options.   
*   `content`       Text to be written, an alternative to source which reference a file.   
*   `source`        File path from where to extract the content, do not use conjointly with content.   
*   `destination`   File path where to write content to.   
*   `backup`        Create a backup, append a provided string to the filename extension or a timestamp if value is not a string.   
*   `append`        Append the content to the destination file. If destination does not exist, the file will be created.   
*   `write`         An array containing multiple transformation where a transformation is an object accepting the options `from`, `to`, `match` and `replace`
*   `ssh`           Run the action on a remote server using SSH, an ssh2 instance or an configuration object used to initialize the SSH connection.   
*   `uid`           File user name or user id
*   `gid`           File group name or group id
*   `mode`          File mode (permission and sticky bits), default to `0666`, in the for of `{mode: 0o744}` or `{mode: "744"}`

`callback`          Received parameters are:   
*   `err`           Error object if any.   
*   `written`      Number of written files.   

The option "append" allows some advance usages. If "append" is 
null, it will add the `replace` value at the end of the file 
if no match if found and if the value is a string. When used 
conjointly with the `match` and `replace` options, it gets even 
more interesting. If append is a string or a regular expression, 
it will place the "replace" string just after the match. An 
append string will be converted to a regular expression such as 
"test" will end up converted as the string "test" is similar to the 
RegExp /^.*test.*$/mg.

Example replacing part of a file using from and to markers
```coffee
mecano.write
  content: 'here we are\n# from\nlets try to replace that one\n# to\nyou coquin'
  from: '# from\n'
  to: '# to'
  replace: 'my friend\n'
  destination: "#{scratch}/a_file"
, (err, written) ->
  # here we are\n# from\nmy friend\n# to\nyou coquin
```

Example replacing a matched line by a string with
```coffee
mecano.write
  content: 'email=david(at)adaltas(dot)com\nusername=root'
  match: /(username)=(.*)/
  replace: '$1=david (was $2)'
  destination: "#{scratch}/a_file"
, (err, written) ->
  # email=david(at)adaltas(dot)com\nusername=david (was root)
```

Example replacing part of a file using a regular expression
```coffee
mecano.write
  content: 'here we are\nlets try to replace that one\nyou coquin'
  match: /(.*try) (.*)/
  replace: ['my friend, $1']
  destination: "#{scratch}/a_file"
, (err, written) ->
  # here we are\nmy friend, lets try\nyou coquin
```

Example replacing with the global and multiple lines options
```coffee
mecano.write
  content: '#A config file\n#property=30\nproperty=10\n#End of Config'
  match: /^property=.*$/mg
  replace: 'property=50'
  destination: "#{scratch}/replace"
, (err, written) ->
  '# A config file\n#property=30\nproperty=50\n#End of Config'
```

Example appending a line after each line containing "property"
```coffee
mecano.write
  content: '#A config file\n#property=30\nproperty=10\n#End of Config'
  match: /^.*comment.*$/mg
  replace: '# comment'
  destination: "#{scratch}/replace"
  append: 'property'
, (err, written) ->
  '# A config file\n#property=30\n# comment\nproperty=50\n# comment\n#End of Config'
```

Example with multiple transformations
```coffee
mecano.write
  content: 'username: me\nemail: my@email\nfriends: you'
  write: [
    match: /^(username).*$/mg
    replace: "$1: you"
  ,
    match: /^email.*$/mg
    replace: ""
  ,
    match: /^(friends).*$/mg
    replace: "$1: me"
  ]
  destination: "#{scratch}/file"
, (err, written) ->
  # username: you\n\nfriends: me
```

    write: (goptions, options, callback) ->
      [goptions, options, callback] = misc.args arguments
      result = child mecano
      finish = (err, written) ->
        callback err, written if callback
        result.end err, written
      misc.options options, (err, options) ->
        return finish err if err
        written = 0
        each( options )
        .parallel(goptions.parallel)
        .on 'item', (options, next) ->
          modified = false
          # Validate parameters
          return next new Error 'Missing source or content' unless (options.source or options.content?) or options.replace or options.write?.length
          return next new Error 'Define either source or content' if options.source and options.content
          return next new Error 'Missing destination' unless options.destination
          destination  = null
          destinationHash = null
          content = null
          #fullContent = null
          from = to = between = null
          append = options.append
          write = options.write
          write ?= []
          if options.from? or options.to? or options.match?
            write.push
              from: options.from
              to: options.to
              match: options.match
              replace: options.replace
              append: options.append
            # append = false
          # Start real work
          readSource = ->
            if options.content?
              content = options.content
              content = "#{content}" if typeof content is 'number'
              return readDestination()
            # Option "local_source" force to bypass the ssh 
            # connection, use by the upload function
            source = options.source or options.destination
            ssh = if options.local_source then null else options.ssh
            misc.file.exists ssh, source, (err, exists) ->
              return next err if err
              unless exists
                return next new Error "Source does not exist: \"#{options.source}\"" if options.source
                content = ''
                return readDestination()
              misc.file.readFile ssh, source, 'utf8', (err, src) ->
                return next err if err
                content = src
                readDestination()
          readDestination = ->
            # no need to test changes if destination is a callback
            return render() if typeof options.destination is 'function'
            exists = ->
              misc.file.exists options.ssh, options.destination, (err, exists) ->
                return next err if err
                if exists then read() else mkdir()
            mkdir = ->
              mecano.mkdir 
                ssh: options.ssh
                destination: path.dirname options.destination
                uid: options.uid
                gid: options.gid
                mode: options.mode
                # We only apply uid and gid if the dir does not yet exists
                not_if_exists: path.dirname options.destination
              , (err, created) ->
                return next err if err
                render()
            read = ->
              misc.file.readFile options.ssh, options.destination, 'utf8', (err, dest) ->
                return next err if err
                destinationHash = misc.string.hash dest
                render()
            exists()
          render = ->
            return replacePartial() unless options.context?
            try
              content = eco.render content.toString(), options.context
            catch err
              err = new Error err if typeof err is 'string'
              return next err
            replacePartial()
          replacePartial = ->
            # return writeContent() unless fullContent?
            return writeContent() unless write.length
            for opts in write
              if opts.match
                if opts.match instanceof RegExp
                  if opts.match.test content
                    content = content.replace opts.match, opts.replace
                    append = false
                  else if opts.append and typeof opts.replace is 'string'
                    if typeof opts.append is "string"
                      opts.append = new RegExp "^.*#{opts.append}.*$", 'mg'
                    if opts.append instanceof RegExp
                      posoffset = 0
                      orgContent = content
                      while (res = opts.append.exec orgContent) isnt null
                        pos = posoffset + res.index + res[0].length
                        content = content.slice(0,pos) + '\n'+opts.replace + content.slice(pos)
                        posoffset += opts.replace.length + 1
                        break unless opts.append.global
                      append = false
                    else
                      linebreak = if content.length is 0 or content.substr(content.length - 1) is '\n' then '' else '\n'
                      content = content + linebreak + opts.replace
                      append = false
                  else
                    # Did not match, try next one
                    continue
                else
                  from = content.indexOf(opts.match)
                  to = from + opts.match.length
                  content = content.substr(0, from) + opts.replace + content.substr(to)
              else
                from = if opts.from then content.indexOf(opts.from) + opts.from.length else 0
                to = if opts.to then content.indexOf(opts.to) else content.length
                content = content.substr(0, from) + opts.replace + content.substr(to)
            writeContent()
          writeContent = ->
            return do_changeOwnership() if destinationHash is misc.string.hash content
            if typeof options.destination is 'function'
              options.destination content
              do_end()
            else
              options.flags ?= 'a' if append
              misc.file.writeFile options.ssh, options.destination, content, options, (err) ->
                return next err if err
                modified = true
                backup()
          backup = ->
            return do_end() unless options.backup
            backup = options.backup
            backup = ".#{Date.now()}" if backup is true
            backup = "#{options.destination}#{backup}"
            misc.file.writeFile options.ssh, backup, content, (err) ->
              return next err if err
              do_end()
          do_changeOwnership = ->
            return do_changePermissions() unless options.uid? and options.gid?
            mecano.chown
              ssh: options.ssh
              destination: options.destination
              uid: options.uid
              gid: options.gid
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, chowned) ->
              return next err if err
              modified = true if chowned
              do_changePermissions()
          do_changePermissions = ->
            return do_end() unless options.mode?
            mecano.chmod
              ssh: options.ssh
              destination: options.destination
              mode: options.mode
              log: options.log
              stdout: options.stdout
              stderr: options.stderr
            , (err, chmoded) ->
              return next err if err
              modified = true if chmoded
              do_end()
          do_end = ->
            written++ if modified
            next()
          conditions.all options, next, readSource
        .on 'both', (err) ->
          finish err, written
      result

    # Alias definitions
    mecano.cp   = mecano.copy
    mecano.exec = mecano.execute
    mecano.ln   = mecano.link
    mecano.mv   = mecano.move
    mecano.rm   = mecano.remove


