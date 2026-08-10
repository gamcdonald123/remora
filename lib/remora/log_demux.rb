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
  end
end
