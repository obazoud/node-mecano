
crypto = require 'crypto'
fs = require 'fs'
path = require 'path'
fs.exists ?= path.exists
each = require 'each'
util = require 'util'
Stream = require 'stream'
exec = require 'superexec'
connect = require 'superexec/lib/connect'
buffer = require 'buffer'
rimraf = require 'rimraf'
ini = require 'ini'

misc = module.exports = 
  string:
    ###
    `string.hash(file, [algorithm], callback)`
    ------------------------------------------
    Output the hash of a supplied string in hexadecimal 
    form. The default algorithm to compute the hash is md5.
    ###
    hash: (data, algorithm) ->
      if arguments.length is 1
        algorithm = 'md5'
      crypto.createHash(algorithm).update(data).digest('hex')
    repeat: (str, l) ->
      Array(l+1).join str
  file:
    readdir: (ssh, path, callback) ->
      unless ssh
        fs.readdir path, callback
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          sftp.readdir path, callback
    ###
    `chown(ssh, path, options, callback)`
    -------------------------------------
    ###
    chown: (ssh, path, uid, gid, callback) ->
      return callback new Error 'Either option "uid" or "gid" is required' unless uid or gid
      unless ssh
        fs.chown path, uid, gid, (err) ->
          callback err
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          sftp.chown path, uid, gid, (err) ->
            sftp.end()
            callback err
    ###
    `chmod(ssh, path, options, callback)`
    -------------------------------------
    ###
    chmod: (ssh, path, mode, callback) ->
      unless ssh
        fs.chmod path, mode, (err) ->
          callback err
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          sftp.chmod path, mode, (err) ->
            sftp.end()
            callback err
    ###
    Compare modes
    -------------
    ###
    cmpmod: (modes...) ->
      ref = modes[0]
      ref = ref.toString(8) if typeof ref is 'number'
      for i in [1...modes.length]
        mode = modes[i]
        mode = mode.toString(8) if typeof mode is 'number'
        l = Math.min ref.length, mode.length
        return false if mode.substr(-l) isnt ref.substr(-l)
      true
    ###
    `createReadStream(ssh, path, [options], callback)`
    --------------------------------------------------

        misc.file.createReadStream sshOrNull, 'test.out', (err, stream) ->
          stream.pipe fs.createWriteStream 'test.in'
    ###
    createReadStream: (ssh, source, options, callback) ->
      if arguments.length is 3
        callback = options
        options = {}
      unless ssh
        callback null, fs.createReadStream source, options
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          s = sftp.createReadStream source, options
          s.emit = ( (emit) ->
            (key, val) ->
              if key is 'error' and val is undefined
                val = new Error "EISDIR, read"
                val.errno = 28
                val.code = 'EISDIR'
                return emit.call @, 'error', val
              if key is 'error' and val.message is 'No such file'
                val = new Error "ENOENT, open '#{source}'"
                val.errno = 34
                val.code = 'ENOENT'
                val.path = source
                return emit.call @, 'error', val
              emit.apply @, arguments
          )(s.emit)
          s.on 'close', ->
            sftp.end()
          callback null, s
    ###
    createWriteStream(ssh, path, [options], callback)
    -------------------------------------------------

        misc.file.createWriteStream sshOrNull, 'test.out', (err, stream) ->
          fs.createReadStream('test.in').pipe stream
    ###
    createWriteStream: (ssh, path, options, callback) ->
      if arguments.length is 3
        callback = options
        options = {}
      unless ssh
        callback null, fs.createWriteStream(path, options)
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          ws = sftp.createWriteStream(path, options)
          ws.on 'close', ->
            sftp.end()
          callback null, ws
    ###
    `unlink(ssh, source, callback)`
    ###
    unlink: (ssh, source, callback) ->
      unless ssh
        fs.unlink source, (err) ->
          callback err
      else
        ssh.sftp (err, sftp) ->
          sftp.unlink source, (err) ->
            sftp.end()
            callback err
    copy: (ssh, source, destination, callback) ->
      unless ssh
        source = fs.createReadStream(u.pathname)
        source.pipe destination
        destination.on 'close', callback
        destination.on 'error', callback
      else
        # todo: use cp to copy over ssh
        callback new Error 'Copy over SSH not yet implemented'
    rename: (ssh, source, destination, callback) ->
      unless ssh
        fs.rename source, destination, (err) ->
          callback err
      else
        ssh.sftp (err, sftp) ->
          sftp.rename source, destination, (err) ->
            sftp.end()
            callback err
    readlink: (ssh, path, callback) ->
      unless ssh
        fs.readlink path, (err, target) ->
          callback err, target
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          sftp.readlink path, (err, target) ->
            sftp.end()
            callback err, target
    unlink: (ssh, path, callback) ->
      unless ssh
        fs.unlink path, (err) ->
          callback err
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          sftp.unlink path, (err) ->
            sftp.end()
            callback err
    symlink: (ssh, targetPath, linkPath, callback) ->
      unless ssh
        fs.symlink targetPath, linkPath, (err) ->
          callback err
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          sftp.symlink targetPath, linkPath, (err) ->
            sftp.end()
            callback err
    lstat: (ssh, path, callback) ->
      unless ssh
        fs.lstat path, (err, stat) ->
          callback err, stat
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          sftp.lstat path, (err, attr) ->
            sftp.end()
            if err and err.type is 'NO_SUCH_FILE'
              err.code = 'ENOENT'
              return callback err
            callback err, attr
    stat: (ssh, path, callback) ->
      # Not yet test, no way to know if file is a direct or a link
      unless ssh
        # { dev: 16777218, mode: 16877, nlink: 19, uid: 501, gid: 20,
        # rdev: 0, blksize: 4096, ino: 1736226, size: 646, blocks: 0,
        # atime: Wed Feb 27 2013 23:25:07 GMT+0100 (CET), mtime: Tue Jan 29 2013 23:29:28 GMT+0100 (CET), ctime: Tue Jan 29 2013 23:29:28 GMT+0100 (CET) }
        fs.stat path, (err, stat) ->
          callback err, stat
      else
        # { size: 646, uid: 501, gid: 20, permissions: 16877, 
        # atime: 1362003965, mtime: 1359498568 }
        ssh.sftp (err, sftp) ->
          return callback err if err
          sftp.stat path, (err, attr) ->
            sftp.end()
            if err and err.type is 'NO_SUCH_FILE'
              err.code = 'ENOENT'
              return callback err
            # attr.mode = attr.permissions
            callback err, attr
    ###
    `readFile(ssh, path, [options], callback)`
    -----------------------------------------
    ###
    readFile: (ssh, source, options, callback) ->
      if arguments.length is 3
        callback = options
        options = {}
      else
        options = encoding: options if typeof options is 'string'
      return callback new Error "Invalid path '#{source}'" unless source
      unless ssh
        fs.readFile source, options.encoding, (err, content) ->
          callback err, content
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          s = sftp.createReadStream source, options
          data = []
          s.on 'data', (d) ->
            data.push d.toString()
          s.on 'error', (err) ->
            err = new Error "ENOENT, open '#{source}'"
            err.errno = 34
            err.code = 'ENOENT'
            err.path = source
            finish err
          s.on 'close', ->
            finish null, data.join ''
          finish = (err, data) ->
            sftp.end()
            callback err, data
    ###
    `writeFile(ssh, path, content, [options], callback)`
    -----------------------------------------
    ###
    writeFile: (ssh, source, content, options, callback) ->
      if arguments.length is 4
        callback = options
        options = {}
      else
        options = encoding: options if typeof options is 'string'
      unless ssh
        # fs.writeFile source, content, options, (err, content) ->
        #   callback err, content
        write = ->
          stream = fs.createWriteStream source, options
          if typeof content is 'string' or buffer.Buffer.isBuffer content
            stream.write content if content
            stream.end()
          else
            content.pipe stream
          stream.on 'error', (err) ->
            callback err
          stream.on 'end', ->
            s.destroy()
          stream.on 'close', ->
            chown()
        chown = ->
          return chmod() unless options.uid or options.gid
          fs.chown source, options.uid, options.gid, (err) ->
            return callback err if err
            chmod()
        chmod = ->
          return finish() unless options.mode
          fs.chmod source, options.mode, (err) ->
            finish err
        finish = (err) ->
          callback err
        write()
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          write = ->
            s = sftp.createWriteStream source, options
            if typeof content is 'string' or buffer.Buffer.isBuffer content
              s.write content if content
              s.end()
            else
              content.pipe s
            s.on 'error', (err) ->
              finish err
            s.on 'end', ->
              s.destroy()
            s.on 'close', ->
              chown()
          chown = ->
            return chmod() unless options.uid or options.gid
            sftp.chown source, options.uid, options.gid, (err) ->
              return finish err if err
              chmod()
          chmod = ->
            return finish() unless options.mode
            sftp.chmod source, options.mode, (err) ->
              finish err
          finish = (err) ->
            sftp.end()
            callback err
          write()
    ###
    `mkdir(ssh, path, [options], callback)`
    -------------------------------------
    Note, if option is not a string, it is considered to be the permission mode.
    ###
    mkdir: (ssh, path, options, callback) ->
      if arguments.length is 3
        callback = options
        options = 0o0755
      if typeof options isnt 'object'
        options = mode: options
      if options.permissions
        process.stderr.write 'Deprecated, use mode instead of permissions'
        options.mode = options.permissions
      unless ssh
        fs.mkdir path, options.mode, (err) ->
          callback err
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          mkdir = ->
            sftp.mkdir path, options, (err, attr) ->
              if err?.message is 'Failure'
                err = new Error "EEXIST, mkdir '#{path}'"
                err.errno = 47
                err.code = 'EEXIST'
                err.path = path
              return finish err if err
              chown()
          chown = ->
            return chmod() unless options.uid or options.gid
            sftp.chown path, options.uid, options.gid, (err) ->
              return finish err if err
              chmod()
          chmod = ->
            return finish() unless options.mode
            sftp.chmod path, options.mode, (err) ->
              finish err
          finish = (err) ->
            sftp.end()
            callback err
          mkdir()
    ###
    `exists(ssh, path, callback)`
    -----------------------------

    `options`         Command options include:   

    *   `ssh`         SSH connection in case of a remote file path.  
    *   `path`        Path to test.   
    *   `callback`    Callback to return the result.   

    `callback`        Received parameters are:   

    *   `err`         Error object if any.   
    *   `exists`      True if the file exists.   
    ###
    exists: (ssh, path, callback) ->
      unless ssh
        fs.exists path, (exists) ->
          callback null, exists
      else
        ssh.sftp (err, sftp) ->
          return callback err if err
          sftp.stat path, (err, attr) ->
            sftp.end()
            callback null, if err then false else true
    ###
    `files.hash(file, [algorithm], callback)`
    -----------------------------------------
    Retrieve the hash of a supplied file in hexadecimal 
    form. If the provided file is a directory, the returned hash 
    is the sum of all the hashs of the files it recursively 
    contains. The default algorithm to compute the hash is md5.

    Throw an error if file does not exist unless it is a directory.

        misc.file.hash ssh, '/path/to/file', (err, md5) ->
          md5.should.eql '287621a8df3c3f6c99c7b7645bd09ffd'

    ###
    hash: (ssh, file, algorithm, callback) ->
      if arguments.length is 3
        callback = algorithm
        algorithm = 'md5'
      hasher = (ssh, path, callback) ->
        shasum = crypto.createHash algorithm
        misc.file.createReadStream ssh, path, (err, stream) ->
          return callback err if err
          stream
          .on 'data', (data) ->
            shasum.update data
          .on 'error', (err) ->
            return callback() if err.code is 'EISDIR'
            callback err
          .on 'end', ->
            callback err, shasum.digest 'hex'
      hashs = []
      misc.file.stat ssh, file, (err, stat) ->
        return callback new Error "Does not exist: #{file}" if err?.code is 'ENOENT'
        return callback err if err
        file += '/**' if stat.isDirectory()
        # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        # This is not working over ssh, we
        # need to implement the "glob" module
        # over ssh
        # |||||||||||||||||||||||||||||||||
        # Temp fix, we support file md5 over
        # ssh, but not directory:
        if ssh and stat.isFile()
          return hasher ssh, file, callback
        each()
        .files(file)
        .on 'item', (item, next) ->
          hasher ssh, item, (err, h) ->
            return next err if err
            hashs.push h if h?
            next()
        .on 'error', (err) ->
          callback err
        .on 'end', ->
          switch hashs.length
            when 0
              if stat.isFile() 
              then callback new Error "Does not exist: #{file}"
              else callback null, crypto.createHash(algorithm).update('').digest('hex')
            when 1
              return callback null, hashs[0]
            else
              hashs = crypto.createHash(algorithm).update(hashs.join('')).digest('hex')
              return callback null, hashs
    ###
    `files.compare(files, callback)`
    --------------------------------
    Compare the hash of multiple file. Return the file md5 
    if the file are the same or false otherwise.
    ###
    compare: (ssh, files, callback) ->
      return callback new Error 'Minimum of 2 files' if files.length < 2
      result = null
      each(files)
      .parallel(true)
      .on 'item', (file, next) ->
        misc.file.hash ssh, file, (err, md5) ->
          return next err if err
          if result is null
            result = md5 
          else if result isnt md5
            result = false 
          next()
      .on 'error', (err) ->
        callback err
      .on 'end', ->
        callback null, result
    ###
    remove(ssh, path, callback)
    ---------------------------
    Remove a file or directory
    ###
    remove: (ssh, path, callback) ->
      unless ssh
        rimraf path, callback
      else
        # Not very pretty but fast and no time to try make a version of rimraf over ssh
        child = exec "rm -rdf #{path}", ssh: ssh
        child.on 'exit', (code) ->
          callback null, code
  ssh:
    ###
    passwd(sftp, [user], callback)
    ----------------------
    Return information present in '/etc/passwd' and cache the 
    result in the provided ssh instance as "passwd".

    Result look like: 
        { root: {
            uid: '0',
            gid: '0',
            comment: 'root',
            home: '/root',
            shell: '/bin/bash' }, ... }
    ###
    passwd: (ssh, username, callback) ->
      if arguments.length is 3
        # Username may be null, stop here
        return callback null, null unless username
        # Is user present in cache
        if ssh.passwd and ssh.passwd[username]
          return callback null, ssh.passwd[username]
        # Relaod the cache and check if user is here
        ssh.passwd = null
        return misc.ssh.passwd ssh, (err, users) ->
          return callback err if err
          user = users[username]
          return callback new Error "User #{username} does not exists" unless user
          callback null, user
      callback = username
      username = null
      # Grab passwd from the cache
      return callback null, ssh.passwd if ssh.passwd
      # Alternative is to use the id command, eg `id -u ubuntu`
      misc.file.readFile ssh, '/etc/passwd', 'ascii', (err, lines) ->
        return callback err if err
        passwd = []
        for line in lines.split '\n'
          info = /(.*)\:\w\:(.*)\:(.*)\:(.*)\:(.*)\:(.*)/.exec line
          continue unless info
          passwd[info[1]] = uid: parseInt(info[2]), gid: parseInt(info[3]), comment: info[4], home: info[5], shell: info[6]
        ssh.passwd = passwd
        callback null, passwd
    ###
    group(sftp, [group], callback)
    ----------------------
    Return information present in '/etc/group' and cache the 
    result in the provided ssh instance as "group".

    Result look like: 
        { root: {
            password: 'x'
            gid: 0,
            user_list: [] },
          bin: {
            password: 'x',
            gid: 1,
            user_list: ['bin','daemon'] } }
    ###
    group: (ssh, group, callback) ->
      if arguments.length is 3
        # Group may be null, stop here
        return callback null, null unless group
        return misc.ssh.group ssh, (err, groups) ->
          return err if err
          group = groups[group]
          return new Error "Group #{group} does not exists" unless group
          callback null, group
      callback = group
      group = null
      # Grab group from the cache
      return callback null, ssh.group if ssh.group
      # Alternative is to use the id command, eg `id -g admin`
      misc.file.readFile ssh, '/etc/group', 'ascii', (err, lines) ->
        return callback err if err
        group = []
        for line in lines.split '\n'
          info = /(.*)\:(.*)\:(.*)\:(.*)/.exec line
          continue unless info
          group[info[1]] = password: info[2], gid: parseInt(info[3]), user_list: if info[4] then info[4].split ',' else []
        ssh.group = group
        callback null, group
  ###
  `pidfileStatus(ssh, pidfile, [options], callback)`
  ---------------------------------------

  Return a status code after reading a status file. Any existing 
  pidfile referencing a dead process will be removed.

  The callback is called with an error and a status code. Values 
  expected as status code are:

  *   0 if pidfile math a running process
  *   1 if pidfile does not exists
  *   2 if pidfile exists but match no process
  ###
  pidfileStatus: (ssh, pidfile, options, callback) ->
    if arguments.length is 3
      callback = options
      options = {}
    misc.file.readFile ssh, pidfile, 'ascii', (err, pid) ->
      # pidfile does not exists
      return callback null, 1 if err and err.code is 'ENOENT'
      return callback err if err
      stdout = []
      run = exec
        cmd: "ps aux | grep #{pid.trim()} | grep -v grep | awk '{print $2}'"
        ssh: ssh
      run.stdout.on 'data', (data) ->
        stdout.push data
      if options.stdout
        run.stdout.pipe options.stdout
      if options.stderr
        run.stderr.pipe options.stderr
      run.on "exit", (code) ->
        stdout = stdout.join('')
        # pidfile math a running process
        return callback null, 0 unless stdout is ''
        misc.file.remove ssh, pidfile, (err, removed) ->
          return callback err if err
          # pidfile exists but match no process
          callback null, 2
  ###
  `isPortOpen(port, host, callback)`: Check if a port is already open

  ###
  isPortOpen: (port, host, callback) ->
    if arguments.length is 2
      callback = host
      host = '127.0.0.1'
    exec "nc #{host} #{port} < /dev/null", (err, stdout, stderr) ->
      return callback null, true unless err
      return callback null, false if err.code is 1
      callback err
  ###
  `merge([inverse], obj1, obj2, ...]`: Recursively merge objects
  --------------------------------------------------------------
  On matching keys, the last object take precedence over previous ones 
  unless the inverse arguments is provided as true. Only objects are 
  merge, arrays are overwritten.

  Enrich an existing object with a second one:
    obj1 = { a_key: 'a value', b_key: 'b value'}
    obj2 = { b_key: 'new b value'}
    result = misc.merge obj1, obj2
    assert.eql result, obj1
    assert.eql obj1.b_key, 'new b value'

  Create a new object from two objects:
    obj1 = { a_key: 'a value', b_key: 'b value'}
    obj2 = { b_key: 'new b value'}
    result = misc.merge {}, obj1, obj2
    assert.eql result.b_key, 'new b value'

  Using inverse:
    obj1 = { b_key: 'b value'}
    obj2 = { a_key: 'a value', b_key: 'new b value'}
    misc.merge true, obj1, obj2
    assert.eql obj1.a_key, 'a value'
    assert.eql obj1.b_key, 'b value'

  ###
  merge: () ->
    target = arguments[0]
    from = 1
    to = arguments.length
    if typeof target is 'boolean'
      inverse = !! target
      target = arguments[1]
      from = 2
    # Handle case when target is a string or something (possible in deep copy)
    if typeof target isnt "object" and typeof target isnt 'function'
      target = {}
    for i in [from ... to]
      # Only deal with non-null/undefined values
      if (options = arguments[ i ]) isnt null
        # Extend the base object
        for name of options 
          src = target[ name ]
          copy = options[ name ]
          # Prevent never-ending loop
          continue if target is copy
          # Recurse if we're merging plain objects
          if copy? and typeof copy is 'object' and not Array.isArray(copy) and copy not instanceof RegExp
            clone = src and ( if src and typeof src is 'object' then src else {} )
            # Never move original objects, clone them
            target[ name ] = misc.merge false, clone, copy
          # Don't bring in undefined values
          else if copy isnt undefined
            target[ name ] = copy unless inverse and typeof target[ name ] isnt 'undefined'
    # Return the modified object
    target
  kadmin: (options, cmd) ->
    if options.kadmin_principal
    then "kadmin -p #{options.kadmin_principal} -s #{options.kadmin_server} -w #{options.kadmin_password} -q '#{cmd}'"
    else "kadmin.local -q '#{cmd}'"
  ini:
    safe: (val) ->
      if ( typeof val isnt "string" or val.match(/[\r\n]/) or val.match(/^\[/) or (val.length > 1 and val.charAt(0) is "\"" and val.slice(-1) is "\"") or val isnt val.trim() )
      then JSON.stringify(val)
      else val.replace(/;/g, '\\;')

    dotSplit: `function (str) {
      return str.replace(/\1/g, '\2LITERAL\\1LITERAL\2')
             .replace(/\\\./g, '\1')
             .split(/\./).map(function (part) {
               return part.replace(/\1/g, '\\.')
                      .replace(/\2LITERAL\\1LITERAL\2/g, '\1')
             })
    }`
    parse: (content, options) ->
      ini.parse content
    ###
    
    Each category is surrounded by one or several square brackets. The number of brackets indicates
    the depth of the category.
    Options are   

    *   `comment`   Default to ";"

    ###
    parse_multi_brackets: (str, options={}) ->
      lines = str.split /[\r\n]+/g
      current = data = {}
      stack = [current]
      comment = options.comment or ';'
      lines.forEach (line, _, __) ->
        return if not line or line.match(/^\s*$/)
        # Category
        if match = line.match /^\s*(\[+)(.+?)(\]+)\s*$/
          depth = match[1].length
          # Add a child
          if depth is stack.length
            parent = stack[depth - 1]
            parent[match[2]] = current = {}
            stack.push current
          # Invaild child hierarchy
          if depth > stack.length
            throw new Error "Invalid child #{match[2]}"
          # Move up or at the same level
          if depth < stack.length
            stack.splice depth, stack.length - depth
            parent = stack[depth - 1]
            parent[match[2]] = current = {}
            stack.push current
        # comment
        else if comment and match = line.match ///^\s*(#{comment}.*)$///
          current[match[1]] = null
        # key value
        else if match = line.match /^\s*(.+?)\s*=\s*(.+)\s*$/
          current[match[1]] = match[2]
        # else
        else if match = line.match /^\s*(.+?)\s*$/
          current[match[1]] = null
      data
    stringify: (obj, section, options) ->
      if arguments.length is 2
        options = section
        section = undefined
      options.separator ?= ' = '
      eol = if process.platform is "win32" then "\r\n" else "\n"
      safe = misc.ini.safe
      dotSplit = misc.ini.dotSplit
      children = []
      out = ""
      Object.keys(obj).forEach (k, _, __) ->
        val = obj[k]
        if val and Array.isArray val
            val.forEach (item) ->
                out += safe("#{k}[]") + options.separator + safe(item) + "\n"
        else if val and typeof val is "object"
          children.push k
        else
          out += safe(k) + options.separator + safe(val) + eol
      if section and out.length
        out = "[" + safe(section) + "]" + eol + out
      children.forEach (k, _, __) ->
        nk = dotSplit(k).join '\\.'
        child = misc.ini.stringify(obj[k], (if section then section + "." else "") + nk, options)
        if out.length and child.length
          out += eol
        out += child
      out
    stringify_square_then_curly: (content, depth=0, options={}) ->
      if arguments.length is 2
        options = depth
        depth = 0
      options.separator ?= ' = '
      out = ''
      indent = ' '
      prefix = ''
      for i in [0...depth]
        prefix += indent
      for k, v of content
        isUndefined = typeof v is 'undefined'
        isBoolean = typeof v is 'boolean'
        isNull = v is null
        isObj = typeof v is 'object' and not isNull
        if isObj
          if depth is 0
            out += "#{prefix}[#{k}]\n"
            out += misc.ini.stringify_square_then_curly v, depth + 1, options
            out += "\n"
          else
            out += "#{prefix}#{k}#{options.separator}{\n"
            out += misc.ini.stringify_square_then_curly v, depth + 1, options
            out += "#{prefix}}\n"
        else 
          if isNull
            out += "#{prefix}#{k}#{options.separator}null"
          else if isBoolean
            out += "#{prefix}#{k}#{options.separator}#{if v then 'true' else 'false'}"
          else
            out += "#{prefix}#{k}#{options.separator}#{v}"
          out += '\n'
      out
    ###
    Each category is surrounded by one or several square brackets. The number of brackets indicates
    the depth of the category.
    ###
    stringify_multi_brackets: (content, depth=0, options={}) ->
      if arguments.length is 2
        options = depth
        depth = 0
      options.separator ?= ' = '
      out = ''
      indent = '  '
      prefix = ''
      for i in [0...depth]
        prefix += indent
      for k, v of content
        isUndefined = typeof v is 'undefined'
        isBoolean = typeof v is 'boolean'
        isNull = v is null
        isObj = typeof v is 'object' and not isNull
        if isObj
            out += "#{prefix}#{misc.string.repeat '[', depth+1}#{k}#{misc.string.repeat ']', depth+1}\n"
            out += misc.ini.stringify_multi_brackets v, depth + 1, options
        else 
          if isNull
            out += "#{prefix}#{k}"
          else if isBoolean
            out += "#{prefix}#{k}#{options.separator}#{if v then 'true' else 'false'}"
          else
            out += "#{prefix}#{k}#{options.separator}#{v}"
          out += '\n'
      out
  args: (args, default_goptions={}) ->
    # [goptions, options, callback] = args
    if args.length is 2 and typeof args[1] is 'function'
      args[2] = args[1]
      args[1] = args[0]
      args[0] = null
    else if args.length is 1
      args[1] = args[0]
      args[0] = null
    args[0] ?= misc.merge default_goptions, parallel: true
    args
  ###

  `options(options, callback)`
  ----------------------------
  Normalize options. An ssh connection is needed if the key "ssh" 
  hold a configuration object. The 'uid' and 'gid' fields will 
  be converted to integer if they match a username or a group.   

  `callback`          Received parameters are:   

  *   `err`           Error object if any.   
  *   `options`       Sanitized options.   

  ###
  options: (options, callback) ->
    options = [options] unless Array.isArray options
    each(options)
    .on 'item', (options, next) ->
      options.if = [options.if] if options.if? and not Array.isArray options.if
      # options.if_exists = options.destination if options.if_exists is true and options.destination
      options.if_exists = [options.if_exists] if options.if_exists? and not Array.isArray options.if_exists
      # options.not_if_exists = options.destination if options.not_if_exists is true and options.destination
      options.not_if_exists = [options.not_if_exists] if options.not_if_exists? and not Array.isArray options.not_if_exists
      if options.if_exists then for el, i in options.if_exists
        options.if_exists[i] = options.destination if el is true and options.destination
      if options.not_if_exists then for v, i in options.not_if_exists
        options.not_if_exists[i] = options.destination if v is true and options.destination
      options.mode ?= options.chmod if options.chmod
      connection = ->
        return next() unless options.ssh
        connect options.ssh, (err, ssh) ->
          return next err if err
          options.ssh = ssh
          mode()
      mode = ->
        options.mode = parseInt(options.mode, 8) if typeof options.mode is 'string'
        uid()
      uid = ->
        return gid() unless options.uid
        return gid() if typeof options.uid is 'number' or /\d+/.test options.uid
        misc.ssh.passwd options.ssh, options.uid, (err, user) ->
          return next err if err
          options.uid = user.uid
          options.gid ?= user.gid
          gid()
      gid = ->
        return next() unless options.gid
        return next() if typeof options.gid is 'number' or /\d+/.test options.gid
        misc.ssh.group options.ssh, options.gid, (err, group) ->
          return next err if err
          options.gid = group.gid if group
          next()
      connection()
    .on 'both', (err) ->
      callback err, options





