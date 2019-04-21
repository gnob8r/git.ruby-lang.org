#!/usr/bin/env ruby

require "test/unit"

test_file = "test/test_*.rb"

$LOAD_PATH.unshift(File.join(File.expand_path("."), "test"))
Dir.glob(test_file) do |file|
  require file
end

