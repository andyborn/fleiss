require 'singleton'
require 'optparse'
require 'yaml'
require 'erb'
require 'logger'

module Fleiss
  class CLI
    include Singleton

    DEFAULT_OPTIONS = {
      config: nil,
      queues: ['default'],
      include: [],
      require: [],
      concurrency: 10,
      wait_time: 1.0,
      logfile: STDOUT,
    }.freeze

    attr_reader :opts

    def initialize
      @opts = DEFAULT_OPTIONS.dup
    end

    def parse!(argv=ARGV)
      parser.parse!(argv)

      # Check config file
      raise ArgumentError, "Unable to find config file in #{opts[:config]}" if opts[:config] && !File.exist?(opts[:config])

      return unless opts[:config]

      # Load config file
      conf = YAML.safe_load(ERB.new(IO.read(opts[:config])).result)
      raise ArgumentError, "File in #{opts[:config]} does not contain a valid configuration" unless conf.is_a?(Hash)

      conf.each do |key, value|
        opts[key.to_sym] = value
      end
    end

    def run!
      return if @worker

      $LOAD_PATH.concat opts[:include]
      opts[:require].each {|n| require n }
      require 'fleiss/worker'

      Signal.trap('TERM') { shutdown }
      Signal.trap('INT')  { shutdown }

      @worker = Fleiss::Worker.new \
        queues: opts[:queues],
        concurrency: opts[:concurrency],
        wait_time: opts[:wait_time],
        logger: Logger.new(opts[:logfile])
      @worker.run
      @worker.wait
    end

    def shutdown
      @worker.shutdown if @worker
    end

    def parser # rubocop:disable Metrics/MethodLength
      @parser ||= begin
        op = OptionParser.new do |o|
          o.on '-C', '--config FILE', 'YAML config file to load' do |v|
            @opts[:config] = v
          end

          o.on '-I [DIR]', 'Specify an additional $LOAD_PATH directory' do |v|
            @opts[:include].push(v)
          end

          o.on '-r', '--require [PATH|DIR]', 'File to require' do |v|
            @opts[:require].push(v)
          end

          o.on '-L', '--logfile PATH', 'path to writable logfile' do |v|
            @opts[:logfile] = v
          end
        end

        op.banner = 'fleiss [options]'
        op.on_tail '-h', '--help', 'Show help' do
          $stdout.puts parser
          exit 1
        end
      end
    end
  end
end
