# htstomp

`htstomp` automatically forwards HTTP posts to STOMP queues.  In its
simplest form, `htstomp` will listen to one or several HTTP paths and
post data that is POSTed to those paths to the STOMP topics under the
same name as the paths to which they were sent.  In that case, data
that is posted using HTTP POST commands will be forwarded to the STOMP
topics without any transformation.

However, `htstomp` also supports plugins.  Through its options, you
will be able to bind procedures to a set of incoming URL paths.  Both
the posted data and the path are passed as arguments to the procedures
and these will be able to both transform data and path, for then
sending to the relevant STOMP topics in their transformed form.  Data
transformation occuring in plugins will be executed within safe Tcl
interpreters, which guarantees maximum flexibility when it comes to
transformation capabilities while guaranteeing security through
encapsulation of all IO and system commands.

All `tcl` files implementing the plugins should be placed in the
directory that is pointed at by the `-exts` option.  Binding between
URL paths and procedures occurs through the `-routes` option.  For
example, starting the program with `-routes "* myproc@myplugin.tcl"`
will arrange for all URL paths matching `*` (glob-style matching,
e.g. all paths in this case) to be routed towards the procedure
`myproc` that can be found in the file `myplugin.tcl`.  Whenever an
HTTP client performs a POST, the procedure would be called with two
arguments:

1. The full path that was requested by the client (since it matched
   `*`).

2. The data that the client sent as part of the `POST` command.

The procedure `myproc` is then free to perform any kind of operations
it deems necessary on both the data and the path.  Once all
transformation has succeeded, it can send the data using the `stomp`
command.  That command is automatically bound to the remote server and
it could look similar to the following pseudo code:

    stomp $path -body $data -type text/plain
