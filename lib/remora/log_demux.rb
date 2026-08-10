module Remora
  # Docker multiplexes stdout/stderr into 8-byte-header frames unless the
  # container runs with a TTY: [stream_type, 0, 0, 0, big-endian length] + payload.
  module LogDemux
    STREAM_TYPES = [ 0, 1, 2 ].freeze

    def self.call(bytes)
      output = +""
      offset = 0
      while offset + 8 <= bytes.bytesize
        type, length = bytes.byteslice(offset, 8).unpack("Cx3N")
        break unless STREAM_TYPES.include?(type)

        output << bytes.byteslice(offset + 8, length).to_s
        offset += 8 + length
      end
      # A truncated trailing frame contributes whatever payload arrived.
      output
    end

    # Stateful variant for follow streams, where frames arrive split across
    # arbitrary chunk boundaries. push returns whatever complete payloads the
    # chunk finished off; partial frames wait in the buffer.
    class Streamer
      def initialize
        @buffer = +"".b
      end

      def push(chunk)
        @buffer << chunk.b
        output = +""
        loop do
          break if @buffer.bytesize < 8

          type, length = @buffer.unpack("Cx3N")
          break unless STREAM_TYPES.include?(type)
          break if @buffer.bytesize < 8 + length

          output << @buffer.byteslice(8, length)
          @buffer = @buffer.byteslice(8 + length, @buffer.bytesize).to_s
        end
        output.force_encoding(Encoding::UTF_8).scrub
      end
    end
  end
end
