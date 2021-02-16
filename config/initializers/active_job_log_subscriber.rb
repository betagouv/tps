require 'active_job/logging'
require 'logstash-event'

class ActiveJobLogSubscriber < ::ActiveJob::LogSubscriber
  def enqueue(event)
    process_event(event, 'enqueue')
  end

  def enqueue_at(event)
    process_event(event, 'enqueue_at')
  end

  def perform(event)
    process_event(event, 'perform')
  end

  def perform_start(event)
    process_event(event, 'perform_start')
  end

  def log(data)
    event = LogStash::Event.new(data)
    event['message'] = "#{data[:job_class]}##{data[:job_id]} at #{data[:scheduled_at]}"
    logger.send(Lograge.log_level, event.to_json)
  end

  def logger
    Lograge.logger.presence || super
  end

  private

  def process_event(event, type)
    data = extract_metadata(event)
    data.merge!(extract_exception(event))

    case type
    when 'enqueue_at'
      data.merge!(extract_scheduled_at(event))
    when 'perform'
      data.merge!(extract_duration(event))
    end

    tags = ['job', type]
    if data[:exception]
      tags.push('exception')
    end
    data[:tags] = tags
    data[:type] = 'tps'
    data[:source] = ENV['SOURCE']

    log(data)
  end

  def extract_metadata(event)
    {
      job_id: event.payload[:job].job_id,
      queue_name: queue_name(event),
      job_class: event.payload[:job].class.to_s,
      job_args: args_info(event.payload[:job])
    }
  end

  def extract_duration(event)
    { duration: event.duration.to_f.round(2) }
  end

  def extract_exception(event)
    event.payload.slice(:exception)
  end

  def extract_scheduled_at(event)
    { scheduled_at: scheduled_at(event) }
  end

  # The default args_info makes a string. We need objects to turn into JSON.
  def args_info(job)
    job.arguments.map { |arg| arg.try(:to_global_id).try(:to_s) || arg }
  end
end
