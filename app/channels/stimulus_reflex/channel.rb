# frozen_string_literal: true

class StimulusReflex::Channel < StimulusReflex.configuration.parent_channel.constantize
  attr_reader :reflex_data

  def stream_name
    ids = connection.identifiers.map { |identifier| send(identifier).try(:id) || send(identifier) }
    [
      params[:channel],
      ids.select(&:present?).join(";")
    ].select(&:present?).join(":")
  end

  def subscribed
    super
    stream_from stream_name
  end

  def receive(data)
    @reflex_data = StimulusReflex::ReflexData.new(data)
    begin
      begin
        reflex = StimulusReflex::ReflexFactory.create_reflex_from_data(self, @reflex_data)
        delegate_call_to_reflex reflex
      rescue => invoke_error
        message = exception_message_with_backtrace(invoke_error)
        body = "Reflex #{reflex_data.target} failed: #{message} [#{reflex_data.url}]"

        if reflex
          reflex.rescue_with_handler(invoke_error)
          reflex.broadcast_message subject: "error", body: body, data: data, error: invoke_error
        else
          puts "\e[31m#{body}\e[0m"

          if body.to_s.include? "No route matches"
            initializer_path = Rails.root.join("config", "initializers", "stimulus_reflex.rb")

            puts <<~NOTE
              \e[33mNOTE: StimulusReflex failed to locate a matching route and could not re-render the page.

              If your app uses Rack middleware to rewrite part of the request path, you must enable those middleware modules in StimulusReflex.
              The StimulusReflex initializer should be located at #{initializer_path}, or you can generate it with:

                $ bundle exec rails generate stimulus_reflex:config

              Configure any required middleware:

                StimulusReflex.configure do |config|
                  config.middleware.use FirstRackMiddleware
                  config.middleware.use SecondRackMiddleware
                end\e[0m

            NOTE
          end
        end
        return
      end

      if reflex.halted?
        reflex.broadcast_message subject: "halted", data: data
      else
        begin
          reflex.broadcast(reflex_data.selectors, data)
        rescue => render_error
          reflex.rescue_with_handler(render_error)
          message = exception_message_with_backtrace(render_error)
          body = "Reflex failed to re-render: #{message} [#{reflex_data.url}]"
          reflex.broadcast_message subject: "error", body: body, data: data, error: render_error
          puts "\e[31m#{body}\e[0m"
        end
      end
    ensure
      if reflex
        commit_session(reflex)
        report_failed_basic_auth(reflex) if reflex.controller?
        reflex.logger&.print
      end
    end
  end

  private

  def object_with_indifferent_access(object)
    return object.with_indifferent_access if object.respond_to?(:with_indifferent_access)
    object.map! { |obj| object_with_indifferent_access obj } if object.is_a?(Array)
    object
  end

  def delegate_call_to_reflex(reflex)
    method_name = reflex_data.method_name
    arguments = reflex_data.arguments
    method = reflex.method(method_name)

    policy = StimulusReflex::ReflexMethodInvocationPolicy.new(method, arguments)

    if policy.no_arguments?
      reflex.process(method_name)
    elsif policy.arguments?
      reflex.process(method_name, *arguments)
    else
      raise ArgumentError.new("wrong number of arguments (given #{arguments.inspect}, expected #{required_params.inspect}, optional #{optional_params.inspect})")
    end
  end

  def commit_session(reflex)
    store = reflex.request.session.instance_variable_get("@by")
    store.commit_session reflex.request, reflex.controller.response
  rescue => e
    message = "Failed to commit session! #{exception_message_with_backtrace(e)}"
    puts "\e[31m#{message}\e[0m"
  end

  def report_failed_basic_auth(reflex)
    if reflex.controller.response.status == 401
      message = "Reflex failed to process controller action \"#{reflex.controller.class}##{reflex.controller.action_name}\" due to HTTP basic auth. Consider adding \"unless: -> { @stimulus_reflex }\" to the before_action or method responible for authentication."
      puts "\e[31m#{message}\e[0m"
    end
  end

  def exception_message_with_backtrace(exception)
    "#{exception}\n#{exception.backtrace.first}"
  end
end
