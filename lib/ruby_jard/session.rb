# frozen_string_literal: true

module RubyJard
  ##
  # Centralized flow control and data storage to feed into screens. Each
  # process supposes to have only one instance of this class.
  # TODO: If attachment event happens after any threads are created, race
  # condition may happen. Should use a mutex to wrap around.
  # TODO: This class is created to store data, but byebug data structures are
  # leaked, and accessible from outside and this doesn't work if screens stay in
  # other processes. Therefore, an internal, jard-specific data mapping should
  # be built.
  class Session
    attr_accessor :threads, :current_frame, :current_backtrace

    def initialize(options = {})
      @options = options
      @started = false
      @session_lock = Mutex.new

      @current_frame = nil
      @current_backtrace = []
      @threads = []
    end

    def start
      return if started?

      ##
      # Globally configure Byebug. Byebug doesn't allow configuration by instance.
      # So, I have no choice.
      # TODO: Byebug autoloaded configuration may override those values.
      Byebug::Setting[:autolist] = false
      Byebug::Setting[:autoirb] = false
      Byebug::Setting[:autopry] = false
      Byebug::Context.processor = RubyJard::ReplProcessor
      # Exclude all files in Ruby Jard source code from the stacktrace.
      Byebug::Context.ignored_files = Byebug::Context.all_files + Dir.glob(
        File.join(
          File.expand_path(__dir__, '../lib'),
          '**',
          '*.rb'
        )
      )
      @started = true
    end

    def started?
      @started == true
    end

    def attach
      start unless started?

      Byebug.attach
      Byebug.current_context.step_out(2, false)
    end

    def update
      current_context = Byebug.current_context
      @current_frame = RubyJard::Frame.new(current_context, current_context.frame.pos)
      @current_backtrace = current_context.backtrace.map.with_index do |_frame, index|
        RubyJard::Frame.new(current_context, index)
      end
      @threads =
        Byebug
        .contexts
        .reject(&:ignored?)
        .map do |context|
          RubyJard::Frame.new(context, 0)
        end
    end

    def lock
      raise RubyJard::Error, 'This method requires a block' unless block_given?

      # TODO: This doesn't solve anything. However, debugging a multi-threaded process is hard.
      # Let's deal with that later.
      @session_lock.synchronize do
        yield
      end
    end
  end
end
