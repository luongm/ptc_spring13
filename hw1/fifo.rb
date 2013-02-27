require 'delivery/reliable'

module FIFODelivery
	include DeliveryProtocol
	import ReliableDelivery => :rd

	state do
		table :buffer, pipe_in.schema				 # to save all messages
		table :counter, [:src, :dst] => [:ident]	 # to save current counter
		table :connections, [:src] => [:dst]		 # to save current connections to see if init new counter or not

		scratch :new_connection, connections.schema	 # [init] temp var to keep track of new connection
		scratch :message_to_send, pipe_in.schema	 # [send] temp var to keep track of next message to send
	end

	bloom :buffering do
		buffer <= pipe_in
	end

	bloom :init do
		# Init a counter if there's no message in the buffer that have the same from and to hosts of the new message
		# NOTE: before this was pipe_in.notin(counter...) but it was buggy, not sure why. They should behave the same
		new_connection <= buffer.notin(counter, src: :src, dst: :dst).each {|m| [m[1], m[0]]}
		counter <= new_connection {|c| [c[0], c[1], 0]}
		connections <+ new_connection
	end

	bloom :send do
		# only send the message that have :src, :dst and :ident same as in :counter
		message_to_send <= (buffer * counter).pairs(src: :src, dst: :dst, ident: :ident).each {|p,c| p}
		rd.pipe_in <= message_to_send
		pipe_sent <= message_to_send # marked as sent
		buffer <- message_to_send # remove sent message from buffer

		# then increment the counter
		counter <+- message_to_send { |m| [m[1], m[0], m[2]+1] }
	end

	bloom :rcv do
		pipe_out <= rd.pipe_out
	end
end