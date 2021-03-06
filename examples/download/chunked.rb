#!/usr/bin/env ruby

require 'async'
require 'async/clock'
require 'async/semaphore'
require_relative '../../lib/async/http/endpoint'
require_relative '../../lib/async/http/client'

Async do
	url = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv"
	
	endpoint = Async::HTTP::Endpoint.parse(url)
	client = Async::HTTP::Client.new(endpoint)
	
	headers = {'user-agent' => 'curl/7.69.1', 'accept' => '*/*'}
	
	file = File.open("products.csv", "w")
	Async.logger.info(self) {"Saving download to #{Dir.pwd}"}
	
	begin
		response = client.get(endpoint.path, headers)
		content_length = nil
		
		if response.success?
			unless response.headers['accept-ranges'].include?('bytes')
				raise "Does not advertise support for accept-ranges: bytes!"
			end
			
			unless content_length = response.body&.length
				raise "Could not determine length of response!"
			end
		end
	ensure
		response&.close
	end
	
	Async.logger.info(self) {"Content length: #{content_length/(1024**2)}MiB"}
	
	parts = []
	offset = 0
	chunk_size = 1024*1024
	
	start_time = Async::Clock.now
	amount = 0
	
	while offset < content_length
		byte_range_start = offset
		byte_range_end = [offset + chunk_size, content_length].min
		parts << (byte_range_start...byte_range_end)
		
		offset += chunk_size
	end
	
	Async.logger.info(self) {"Breaking download into #{parts.size} parts..."}
	
	semaphore = Async::Semaphore.new(8)
	
	while !parts.empty?
		semaphore.async do
			part = parts.shift
			
			Async.logger.info(self) {"Issuing range request range: bytes=#{part.min}-#{part.max}"}
			
			response = client.get(endpoint.path, [
				["range", "bytes=#{part.min}-#{part.max-1}"],
				*headers
			])
			
			if response.success?
				Async.logger.info(self) {"Got response: #{response}... writing data for #{part}."}
				written = file.pwrite(response.read, part.min)
				
				amount += written
				
				duration = Async::Clock.now - start_time
				Async.logger.info(self) {"Rate: #{((amount.to_f/(1024**2))/duration).round(2)}MiB/s"}
			end
		end
	end
ensure
	client&.close
end
