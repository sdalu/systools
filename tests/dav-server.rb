# frozen_string_literal: true

# dav-server.rb -- the CalDAV and CardDAV server the caldav and carddav
# tests talk to, on 127.0.0.1 only, so the suite reaches no real server.
#
# usage: ruby tests/dav-server.rb ROOT PORTFILE LOG
#
# A URL path is a path under ROOT.  A directory holding a .props file is
# a collection, its lines "key=value": kind (calendar or addressbook),
# displayname, components (VEVENT,VTODO), and calendar-color and
# calendar-description, which PROPPATCH sets and removes.  Any other
# file in a collection is a resource, its ETag a digest of its content.
#
# It answers what the tools send: PROPFIND (Depth 1: the collections
# under a home; Depth 0: one collection's properties), REPORT (every
# resource of a collection holding the component asked for, a VEVENT
# kept only when its DTSTART and DTEND, read as UTC, overlap the
# time-range; no recurrence is expanded), GET, PUT and DELETE with
# If-Match and If-None-Match, and PROPPATCH.  A request without Basic
# credentials gets 401.  Each request is logged to LOG as one line,
# "VERB PATH user=U depth=D if-match=E if-none-match=E", and the port
# chosen is written to PORTFILE once it listens.

require "base64"
require "digest"
require "socket"

# One request on a socket, and its answer.
class Exchange
    Request = Data.define(:verb, :path, :headers, :body)

    def self.read(socket)
        line = socket.gets or return
        verb, target = line.split
        headers = {}
        while (field = socket.gets) && field != "\r\n"
            key, value = field.split(":", 2)
            headers[key.downcase] = value.strip
        end
        length = headers.fetch("content-length", "0").to_i
        body = length.positive? ? socket.read(length) : ""
        Request.new(verb:, path: target.split("?").first, headers:, body:)
    end

    def self.write(socket, status, body = "", headers = {})
        head = ["HTTP/1.1 #{status}", "Content-Length: #{body.bytesize}",
                "Connection: close",
                *headers.map { |key, value| "#{key}: #{value}" }]
        socket.write("#{head.join("\r\n")}\r\n\r\n#{body}")
    end
end

# The store: collections and resources as directories and files.
class Store
    def initialize(root) = @root = File.expand_path(root)

    def file(path) = File.join(@root, path.delete_prefix("/"))
    def etag(path) = %("#{Digest::SHA1.file(file(path)).hexdigest[0, 16]}")
    def collection?(path) = File.file?(File.join(file(path), ".props"))

    def props(path)
        File.readlines(File.join(file(path), ".props"), chomp: true)
            .filter_map { it.split("=", 2) if it.include?("=") }.to_h
    end

    def save_props(path, props)
        File.write(File.join(file(path), ".props"),
                   props.map { |key, value| "#{key}=#{value}\n" }.join)
    end

    def collections(path)
        Dir.children(file(path)).sort
           .map { "#{path.chomp("/")}/#{it}/" }.select { collection?(it) }
    end

    def resources(path)
        Dir.children(file(path)).sort.reject { it.start_with?(".") }
           .map { "#{path.chomp("/")}/#{it}" }
    end
end

# The DAV verbs, each answering on the socket.
class Server
    XMLNS = 'xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" ' \
            'xmlns:card="urn:ietf:params:xml:ns:carddav" ' \
            'xmlns:a="http://apple.com/ns/ical/"'

    def initialize(store, log)
        @store = store
        @log = log
    end

    def serve(socket)
        req = Exchange.read(socket) or return
        user = credentials(req)
        log(req, user)
        return Exchange.write(socket, "401 Unauthorized") if user.nil?

        status, body, headers = answer(req)
        Exchange.write(socket, status, body.to_s, headers || {})
    end

    private

    def credentials(req)
        auth = req.headers["authorization"].to_s
        return unless auth.start_with?("Basic ")

        Base64.decode64(auth.delete_prefix("Basic ")).split(":", 2).first
    end

    def log(req, user)
        File.open(@log, "a") do |out|
            out.puts [req.verb, req.path, "user=#{user}",
                      "depth=#{req.headers["depth"]}",
                      "if-match=#{req.headers["if-match"]}",
                      "if-none-match=#{req.headers["if-none-match"]}"]
                     .join(" ")
        end
    end

    def answer(req)
        case req.verb
        when "PROPFIND"  then propfind(req)
        when "REPORT"    then report(req)
        when "GET"       then get(req)
        when "PUT"       then put(req)
        when "DELETE"    then delete(req)
        when "PROPPATCH" then proppatch(req)
        else ["405 Method Not Allowed"]
        end
    end

    def multistatus(responses)
        ["207 Multi-Status",
         %(<?xml version="1.0"?>\n<d:multistatus #{XMLNS}>) \
         "#{responses.join}</d:multistatus>",
         { "Content-Type" => "application/xml; charset=utf-8" }]
    end

    def propfind(req)
        return ["404 Not Found"] unless File.directory?(@store.file(req.path))
        return multistatus([collection_props(req.path)]) if
            req.headers["depth"] == "0"

        multistatus(@store.collections(req.path).map { describe(it) })
    end

    def describe(path)
        props = @store.props(path)
        kind  = props["kind"] == "addressbook" ? "card:addressbook" :
                                                 "c:calendar"
        comps = props.fetch("components", "").split(",")
                     .map { %(<c:comp name="#{it}"/>) }.join
        "<d:response><d:href>#{path}</d:href><d:propstat><d:prop>" \
            "<d:displayname>#{props["displayname"]}</d:displayname>" \
            "<d:resourcetype><d:collection/><#{kind}/></d:resourcetype>" \
            "<c:supported-calendar-component-set>#{comps}" \
            "</c:supported-calendar-component-set>" \
            "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>" \
            "</d:response>"
    end

    def collection_props(path)
        props = @store.props(path)
        names = { "displayname" => "d:displayname",
                  "calendar-color" => "a:calendar-color",
                  "calendar-description" => "c:calendar-description" }
        have, missing = names.partition { |key, _| props.key?(key) }
        "<d:response><d:href>#{path}</d:href>" \
            "#{propstat(have.map { |k, n| "<#{n}>#{props[k]}</#{n}>" }, 200)}" \
            "#{propstat(missing.map { |_, n| "<#{n}/>" }, 404)}</d:response>"
    end

    def propstat(props, code)
        return "" if props.empty?

        text = code == 200 ? "OK" : "Not Found"
        "<d:propstat><d:prop>#{props.join}</d:prop>" \
            "<d:status>HTTP/1.1 #{code} #{text}</d:status></d:propstat>"
    end

    def report(req)
        card = req.body.include?("addressbook-query")
        tag  = card ? "card:address-data" : "c:calendar-data"
        hits = @store.resources(req.path).select { wanted?(it, req.body) }
        multistatus(hits.map do |path|
            data = File.read(@store.file(path), encoding: "UTF-8")
            "<d:response><d:href>#{path}</d:href><d:propstat><d:prop>" \
                "<d:getetag>#{@store.etag(path)}</d:getetag>" \
                "<#{tag}>#{xml_escape(data)}</#{tag}>" \
                "</d:prop><d:status>HTTP/1.1 200 OK</d:status>" \
                "</d:propstat></d:response>"
        end)
    end

    # A resource holds the component of the inner comp-filter, and a
    # VEVENT overlaps its time-range.
    def wanted?(path, query)
        data = File.read(@store.file(path), encoding: "UTF-8")
        comp = query.scan(/comp-filter name="([A-Z]+)"/).flatten[1]
        return true if comp.nil?
        return false unless data.include?("BEGIN:#{comp}")

        range = query.match(/time-range start="(\w+)" end="(\w+)"/) or
            return true
        overlaps?(data, range[1], range[2])
    end

    def overlaps?(data, from, to)
        start = stamp(data[/^DTSTART[^:]*:(\S+)/, 1]) or return true
        stop  = stamp(data[/^DTEND[^:]*:(\S+)/, 1]) || start
        stop  = start + 86_400 if stop == start && data =~ /^DTSTART;VALUE=DATE/
        start < stamp(to) && stop > stamp(from)
    end

    def stamp(text)
        return if text.nil?

        m = text.match(/\A(\d{4})(\d\d)(\d\d)(?:T(\d\d)(\d\d)(\d\d))?/) or
            return
        Time.utc(*m.captures.map(&:to_i))
    end

    def xml_escape(text)
        text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def get(req)
        path = @store.file(req.path)
        return ["404 Not Found"] unless File.file?(path)

        ["200 OK", File.binread(path), { "ETag" => @store.etag(req.path) }]
    end

    def put(req)
        path = @store.file(req.path)
        return ["412 Precondition Failed"] unless precondition?(req, path)

        existed = File.file?(path)
        File.binwrite(path, req.body)
        [existed ? "204 No Content" : "201 Created", "",
         { "ETag" => @store.etag(req.path) }]
    end

    def precondition?(req, path)
        exists = File.file?(path)
        return !exists if req.headers["if-none-match"] == "*"

        wanted = req.headers["if-match"] or return true
        exists && wanted == @store.etag(req.path)
    end

    def delete(req)
        path = @store.file(req.path)
        return ["404 Not Found"] unless File.file?(path)
        return ["412 Precondition Failed"] unless precondition?(req, path)

        File.delete(path)
        ["204 No Content"]
    end

    def proppatch(req)
        props = @store.props(req.path)
        names = %w[displayname calendar-color calendar-description]
        set, remove = req.body.split(/<d:remove\b/, 2)
        names.each do |name|
            value = set.to_s[%r{<\w+:#{name}>(.*?)</\w+:#{name}>}m, 1]
            props[name] = value if value
            props.delete(name) if remove.to_s.include?(":#{name}")
        end
        @store.save_props(req.path, props)
        multistatus(["<d:response><d:href>#{req.path}</d:href>" \
                     "#{propstat(["<d:displayname/>"], 200)}</d:response>"])
    end
end

root, portfile, log = ARGV
server = TCPServer.new("127.0.0.1", 0)
File.write("#{portfile}.new", server.addr[1].to_s)
File.rename("#{portfile}.new", portfile)
dav = Server.new(Store.new(root), log)
loop do
    socket = server.accept
    begin
        dav.serve(socket)
    rescue StandardError => e
        warn "dav-server: #{e.class}: #{e.message}"
        Exchange.write(socket, "500 Internal Server Error")
    ensure
        socket.close
    end
end
