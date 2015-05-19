FROM efrecon/mini-tcl
MAINTAINER Emmanuel Frecon <emmanuel@sics.se>

# Copy files, arrange to copy the READMEs, which will also create the
# relevant directories.
COPY *.tcl /opt/htstomp/
COPY lib/*.md /opt/htstomp/lib/
COPY exts/*.md /opt/htstomp/exts/

# Install git so we can install dependencies
RUN apk add --update-cache git

# Install tsdb into /opt and til in the lib subdirectory
WORKDIR /tmp
RUN git clone https://github.com/efrecon/tcl-stomp
RUN mv /tmp/tcl-stomp/lib/stomp /opt/htstomp/lib/
WORKDIR /opt/htstomp/lib
RUN git clone https://github.com/efrecon/til
RUN rm -rf /var/cache/apk/*
WORKDIR /opt/htstomp

# Expose the default HTTP incoming port.
EXPOSE 8080

# Export the plugin directory so it gets easy to test new plugins.
VOLUME /opt/htstomp/exts

ENTRYPOINT ["tclsh8.6", "/opt/htstomp/htstomp.tcl"]
CMD ["-verbose", "notice"]
