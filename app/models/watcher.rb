class Watcher

  include Utilities

  def convert_message_to_hash(message)
    YAML.load(message.body)    
  end

  def create_worker(hash)
    Worker.new(hash)    
  end

  def process(worker, message)
    message.delete if worker.run
  end

  def check_queue
    begin
      # If we have messages on the queue
      message = MessageQueue.get(:name => 'node', :peek => false)
      process(create_worker(convert_message_to_hash(message)), message)
    rescue Exception => e
      HoptoadNotifier.notify(
        :error_class => "Watcher Error", 
        :error_message => "Watcher Error: #{e.message}", 
        :request => { :params => { :message => message } }
      )
      # ensure the message is deleted if we get a NoSuchKey error, since it will continue to fail
      message.delete if e.message =~ /NoSuchKey/
    end
  end

  def run(looping_infinitely = true)
    begin
      check_queue
    end while looping_infinitely
  end

end

