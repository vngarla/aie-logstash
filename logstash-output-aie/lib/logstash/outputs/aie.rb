# Copyright 2014 Attivio Inc., All rights reserved
require "logstash/outputs/base"
require "logstash/namespace"
require "net/http"
require "json"
require "securerandom"
### A custom output plugin for Logstash -> AIE
### Uses 4.0's RESTful JSON Ingest API to send query logs directly to AIE
class LogStash::Outputs::Aie < LogStash::Outputs::Base
   
    config_name "aie"
    milestone 1
     
    # The name of the node to post to
    config :node, :validate => :string, :required => true
    # The port to post to
    config :port, :validate => :string, :required => true
	# The ingest workflow
	config :ingestWorkflowName, :validate => :string, :required => false, :default => "ingest"
	
    # The number of docs to buffer before POSTing to the ingestAPI
    # Note that the docs will not be POSTed until buffer_size 
    # has been met
    config :buffer_size, :validate => :number, :default => 100 

	# session config for aie ingestclient
	config :session_config, :default => {
		"sessionTimeout" => -1,
		"ingestWorkflowName" => "ingest",
		"documentBatchSize" => @buffer_size
	}

    ###### SETUP ######
    public 
    def register()
        # grab the session ID
        @http = Net::HTTP.new(@node, @port)
        @uri_format = "http://#{@node}:#{@port}/rest/ingestApi/%s"
        # set up other instance variables
        @buffer_size = 0;
        @doc_list = Array.new
		connect() 
    end #def register
    #################
	# set up a session
	private
	def connect() 
	    # start a session
		connect_ok = false
		# grab the session ID
        connectURI = URI.parse(@uri_format % [ "connect" ])
		request = Net::HTTP::Post.new(connectURI.path, initheader = {'Content-Type' =>'application/json', 'Accept' => 'application/json'})
		request.body = @session_config.to_json
		connectResponse = @http.request(request)
		if connectResponse.code.to_i != 200
			@logger.warn("error connecting " + connectResponse.body)
		else        
			@session_id = connectResponse.body.gsub(/\"/, "")
			if @session_id.length == 0
				@logger.warn("no session id")
			else
				connect_ok = true
			end
		end
		return connect_ok
	end
    public
    def receive(event)
        # output? is some function provided by the base class (which is provided by logstash)
        return unless output?(event) 
        @doc_list << event_to_doc(event)
        #If we've maxed out the buffer
        if @doc_list.length >= @buffer_size
            do_post(@doc_list, 1)
			# clear out the doc_list
            @doc_list = [ ]
        end
    end #def receive(event)
    private
    def event_to_doc(event)
        hashed_event = event.to_hash
        fields = Hash.new
        # add each key/value to our hash unless value is nil
        hashed_event.each do |field,value| 
			if value
				if value.kind_of?(Array)
					fields[field] = value
				else
					fields[field] = [ value ]
				end
			end
        end
		# generate a uuid if the document id isn't specified
		id = hashed_event[".id"]
		if id.empty? || id.length
			id = SecureRandom.uuid()
		end
        doc = 
        {
            "fields" => fields,
            "id" => id
        }
        return doc
    end #def event_to_doc
     
    private
    def do_post(payload, retries_remaining)
		if payload.length == 0
			return
		end
		# session ID ok, now feed the documents
		begin
			ingest_path = "feedDocuments/%s" % @session_id.to_s
			postUri = URI.parse(URI.encode(@uri_format % ingest_path))
			# construct our request
			request = Net::HTTP::Post.new(postUri.path, initheader = {'Content-Type' =>'application/json', 'Accept' => 'application/json'})
			request.body = payload.to_json
			@logger.debug("posting " + request.body)
			# POST up
			response = @http.request(request)
			if response.code.to_i != 200
				# error - reconnect and retry if we have any retries left
				if retries_remaining >0 && connect()
					do_post(payload, retries_remaining-1)
				else
					@logger.warn("error posting: " + response.body)
				end
			end
		end
    end #def do_post(payload)
end
