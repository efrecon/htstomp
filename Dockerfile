FROM efrecon/tcl
MAINTAINER Emmanuel Frecon <emmanuel@sics.se>

# Set the env variable DEBIAN_FRONTEND to noninteractive to get
# apt-get working without error output.
ENV DEBIAN_FRONTEND noninteractive

# Update underlying ubuntu image and all necessary packages.
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y subversion

# Copy files, arrange to copy the READMEs, which will also create the
# relevant directories.
COPY *.tcl /opt/htstomp/
COPY lib/*.md /opt/htstomp/lib/
COPY exts/*.md /opt/htstomp/exts/

RUN svn checkout https://github.com/efrecon/tcl-stomp/trunk/lib/stomp /opt/htstomp/lib/stomp
RUN svn checkout http://efr-tools.googlecode.com/svn/trunk/til /opt/htstomp/lib/til

# Expose the default HTTP incoming port.
EXPOSE 8080

# Export the plugin directory so it gets easy to test new plugins.
VOLUME /opt/htstomp/exts

ENTRYPOINT ["tclsh8.6", "/opt/htstomp/htstomp.tcl"]
CMD ["-verbose", "notice"]
