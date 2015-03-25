#! /usr/bin/env tclsh

##################
## Program Name    --  htstomp.tcl
## Original Author --  Emmanuel Frecon - emmanuel@sics.se
## Description:
##
##    Converts HTTP post requests into STOMP posting.  Requests can
##    pass through free-form plugins to treat and convert data and/or
##    STOMP topics.
##
##################

set prg_args {
    -help     ""          "Print this help and exit"
    -verbose  3           "Verbosity level \[0-6\]"
    -port     61613       "Port to send to"
    -host     localhost   "Hostname of remote server"
    -user     ""          "Username to authenticate with"
    -password ""          "Password to authenticate with"
    -tls      false       "Encrypt traffic using TLS?"
    -cafile   ""          "Path to CA file, if relevant"
    -certfile ""          "Path to cert file, if relevant"
    -keyfile  ""          "Path to key file, if relevant"
    -http     "http:8080" "List of protocols and ports for HTTP servicing"
    -exts     "%prgdir%/exts" "Path to plugins directory"
    -routes   "* -"       "Topic routing: default is direct mapping of ALL reqs!"
}

set dirname [file dirname [file normalize [info script]]]
set appname [file rootname [file tail [info script]]]
lappend auto_path [file join $dirname lib] [file join $dirname lib til]

package require stomp::client
package require minihttpd


# Dump help based on the command-line option specification and exit.
proc ::help:dump { { hdr "" } } {
    global appname

    if { $hdr ne "" } {
	puts $hdr
	puts ""
    }
    puts "NAME:"
    puts "\t$appname - A STOMP forwarder, HTTP --> STOMP topic"
    puts ""
    puts "USAGE"
    puts "\t${appname}.tcl \[options\]"
    puts ""
    puts "OPTIONS:"
    foreach { arg val dsc } $::prg_args {
	puts "\t${arg}\t$dsc (default: ${val})"
    }
    exit
}

proc ::getopt {_argv name {_var ""} {default ""}} {
    upvar $_argv argv $_var var
    set pos [lsearch -regexp $argv ^$name]
    if {$pos>=0} {
	set to $pos
	if {$_var ne ""} {
	    set var [lindex $argv [incr to]]
	}
	set argv [lreplace $argv $pos $to]
	return 1
    } else {
	# Did we provide a value to default?
	if {[llength [info level 0]] == 5} {set var $default}
	return 0
    }
}

array set FWD {
    plugins   {}
    loglevels {1 critical 2 error 3 warn 4 notice 5 info 6 debug}
}
foreach {arg val dsc} $prg_args {
    set FWD($arg) $val
}

if { [::getopt argv "-help"] } {
    ::help:dump
}

for {set eaten ""} {$eaten ne $argv} {} {
    set eaten $argv
    foreach opt [array names FWD -*] {
	::getopt argv $opt FWD($opt) $FWD($opt)
    }
}

# Arguments remaining?? dump help and exit
if { [llength $argv] > 0 } {
    ::help:dump "$argv are unknown arguments!"
}


# ::forward -- HTTP router
#
#       This procedure is called back whenever one of the HTTP path
#       matching the routes specified as part of the -routes option
#       matches.  The route should either be an empty string or the
#       dash, in which case the data posted is forwarded to the same
#       STOMP topic as the path of the HTTP request.  Otherwise, the
#       route should be the name of a procedure followed by the @-sign
#       followed by the path to a plugin.  The procedure will be
#       called with the identifier of the STOMP connection, the path
#       of the HTTP request and the posted data.  It will be able to
#       send STOMP data using a command called stomp, to the topic
#       that it decides.
#
# Arguments:
#	route	Destination for data (see above).
#	prt	Port of the HTTP server at which request was received
#	sock	Socket to client at the time of the request
#	url	Path requested
#	qry	HTTP query data
#
# Results:
#       None.
#
# Side Effects:
#       Forwards data to STOMP topics, either directly or through
#       plugins.
proc ::forward { route prt sock url qry } {
    global FWD

    # Get to data for the query (i.e. what was sent through the POST).
    # We won't do anything if no data is present once we've trimmed
    # it.
    set data [string trim [::minihttpd::data $prt $sock]]
    if { $data ne "" } {
	$FWD(log)::debug "Incoming POST data on $prt with path $url"
	# If we don't have a route specified, then we simply believe
	# that the path of the HTTP request is the same than the STOMP
	# topic and we forward all data on that topic.
	if { $route eq "" || $route eq "-" } {
	    $FWD(log)::debug "Passing data to STOMP server, topic: $url"
	    ::stomp::client::send $FWD(client) $url \
		-body $data \
		-type text/plain
	} else {
	    # Otherwise, we call the specified procedure within the
	    # safe interpreter (as long as it exists, but it should
	    # have been created as part of the initialisation
	    # process).  The procedure should arrange itself to call
	    # the command called stomp, which really is an alias for
	    # ::stomp::client::send.
	    foreach {proc fname} [split $route "@"] break
	    if { [lsearch $FWD(plugins) $fname] >= 0 \
		     && [interp exists $fname] } {
		# Pass STOMP client identifier, requested URL and
		# POSTed data to the plugin procedure.
		if { [catch {$fname eval [list $proc $url $data]} err] } {
		    $FWD(log)::warn "Error when calling back $proc: $err"
		} else {
		    $FWD(log)::debug "Successfully called $proc for $url: $err"
		}
	    }
	}
    }
}


# ::http:init -- Initialise HTTP listening on port
#
#       Start serving HTTP requests on the port passed as an argument.
#       We arrange for not servicing any file and for the internal
#       procedure forwarder to be called for the routes specified as
#       part of the -routes options.  forwarder will be in charge of
#       forwarding data to STOMP topics, possibly through the
#       specified plugins.
#
# Arguments:
#	port	HTTP port to listen on.
#
# Results:
#       Return the identifier of the server (an integer), negative on
#       errors.
#
# Side Effects:
#       None.
proc ::http:init { port } {
    global FWD

    $FWD(log)::notice "Starting to serve HTTP request on port $port"
    set srv [::minihttpd::new "" $port]
    if { $srv < 0 } {
	return -1
    }
    
    foreach { path route } $FWD(-routes) {
	::minihttpd::handler $srv $path [list ::forward $route] "text/plain"
    }

    return $srv
}


# ::htinit -- Initialise all HTTP servers.
#
#       Loops through the -http option to start serving for HTTP (or
#       HTTPS later?) requests on the pinpointed ports.
#
# Arguments:
#       None.
#
# Results:
#       None.
#
# Side Effects:
#       Start serving for HTTP requests!
proc ::htinit {} {
    global FWD

    foreach p $FWD(-http) {
	set srv -1
	
	if { [string is integer -strict $p] } {
	    set srv [::http:init $p]
	} elseif { [string first ":" $p] >= 0 } {
	    foreach {proto port} [split $p ":"] break
	    switch -nocase -- $proto {
		"HTTP" {
		    set srv [::http:init $port]
		}
	    }
	}
	
	if { $srv > 0 } {
	    lappend FWD(servers) $srv
	}
    }
}

# ::plugin:init -- Initialise plugin facility
#
#       Loops through the specified routes to create and initialise
#       the requested plugins.  Each plugin filename will lead to the
#       creation of a safe interpreter with the same name.  The
#       content of the file will be sourced in the interpreter and the
#       interpreter will be donated a command called "stomp" that is
#       an alias for ::stomp::client::send and that can be used to
#       send data.
#
# Arguments:
#	stomp	Identifier of STOMP client connection
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::plugin:init { stomp } {
    global FWD

    foreach { path route } $FWD(-routes) {
	foreach {proc fname} [split $route "@"] break
	set pdir [string map \
		      [list %prgdir% $::dirname \
			   %appname% $::appname \
			   %prgname% $::appname] \
		      $FWD(-exts)]
	set plugin [file join $pdir $fname]

	if { [file exists $plugin] && [lsearch $FWD(plugins) $fname] <0 } {
	    $FWD(log)::info "Loading plugin at $plugin"
	    set slave [::safe::interpCreate $fname]
	    if { [catch {$slave invokehidden source $plugin} res] == 0 } {
		lappend FWD(plugins) $slave
		$slave alias stomp ::stomp::client::send $stomp
		$slave alias debug $FWD(log)::debug
	    }
	}
    }
    return ""

}

# Start TLS encryption of STOMP connection.
proc ::tlssocket { args } {
    global FWD

    if { [catch {eval [linsert $args 0 ::tls::socket \
			   -tls1 1 \
			   -cafile $FWD(-cafile) \
			   -certfile $FWD(-certfile) \
			   -keyfile $FWD(-keyfile)]} sock] == 0 } {
	fconfigure $sock -blocking 1 -encoding binary
	::tls::handshake $sock
	return $sock
    }
    return -code error $sock
}

# Fix verbosity and logging for all (sub-)modules
if { ![string is integer $FWD(-verbose)] } {
    foreach {i s} $FWD(loglevels) {
	if { [string match -nocase $FWD(-verbose) $s] } {
	    set FWD(-verbose) $i
	    break
	}
    }
}
package require logger
set FWD(log) [::logger::init  $appname]
array set LVL $FWD(loglevels)
if { [info exists LVL($FWD(-verbose))] } {
    $FWD(log)::setlevel $LVL($FWD(-verbose))
    ::minihttpd::loglevel $LVL($FWD(-verbose))
}
::stomp::verbosity $FWD(-verbose)

# Initialise STOMP connection and verbosity.
$FWD(log)::notice "Connecting to STOMP server at $FWD(-host):$FWD(-port)"
if { [string is true $FWD(-tls)] } {
    package require tls
    set FWD(client) [::stomp::client::connect \
			 -host $FWD(-host) \
			 -port $FWD(-port) \
			 -user $FWD(-user) \
			 -password $FWD(-password) \
			 -socketCmd ::tlssocket]
} else {
    set FWD(client) [::stomp::client::connect \
			 -host $FWD(-host) \
			 -port $FWD(-port) \
			 -user $FWD(-user) \
			 -password $FWD(-password)]
}

# Read list of recognised plugins out from the routes.  Plugins are
# only to be found in the directory specified as part of the -exts
# option.  Each file will be sourced into a safe interpreter and will
# be given the command called "stomp" to be able to output to topics.
plugin:init $FWD(client)
# Initialise HTTP reception.  We can listen on several ports, but we
# will only listen to the path as specified through the routes.
htinit

vwait forever
