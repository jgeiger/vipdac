class Unpacker

  include Utilities
  
  attr_accessor :message

  def initialize(message)
    self.message = message
  end

  def run
    begin
      send_job_message(JOBUNPACKING)
      make_directory(UNPACK_DIR)
      download_file(local_mgf_file, remote_mgf_file)
      download_file(local_parameter_file, remote_parameter_file)
      split_original_mgf
      upload_split_mgf_files
      send_job_message(JOBUNPACKED)
    end
    ensure
      remove_item(UNPACK_DIR)
  end

  def local_mgf_file
    "#{UNPACK_DIR}/#{message[:datafile]}"
  end

  def local_parameter_file
    "#{UNPACK_DIR}/#{PARAMETER_FILENAME}"
  end

  def write_file(filename, text)
    File.open(filename, 'w') do |out|
      out.write(text)
    end
  end

  def split_original_mgf
    # split the mgf file from the zip into message[:spectra_count] spectra parts (defaults to 200)
    ions = 0
    filecount = 0
    input_name = input_file(mgf_filename).split('.').first

    mgf_dir = "#{UNPACK_DIR}/mgfs"
    remove_item(mgf_dir)
    make_directory(mgf_dir)

    text = ""
    outfile = ""
    File.open(mgf_filename).each do |line|
      outfile = setup_filename(filecount, mgf_dir, input_name)
      text << line
      ions+=1 if line =~ /END IONS/
      if (ions == message[:spectra_count])
        write_file(outfile, text)
        ions = 0
        filecount+=1
        text = ""
      end
    end
    write_file(outfile, text)
  end

  def setup_filename(count, dir, input)
    filenumber = "%08d" % count
    outfile = "#{dir}/#{input}-#{filenumber}.mgf"
  end

  def send_job_message(type)
    hash = {:type => type, :job_id => message[:job_id]}
    MessageQueue.put(:name => 'head', :message => hash.to_yaml, :priority => 100, :ttr => 60)
  end

  def upload_split_mgf_files
    mgf_filenames.each do |file|
      send_file(bucket_object(file), file)
      send_created_message(file)
    end
  end

  def send_created_message(file)
    bytes = File.size(file)
    sendtime = Time.now.to_f
    chunk_key = Digest::SHA1.hexdigest("#{bucket_object(file)}--#{sendtime}")
    created = {:type => CREATED, :chunk_count => mgf_filenames.size, :bytes => bytes, :sendtime => sendtime, :chunk_key => chunk_key, :job_id => message[:job_id], :filename => bucket_object(file), :parameter_filename => bucket_object(PARAMETER_FILENAME), :bucket_name => message[:bucket_name], :searcher => message[:searcher]}
    MessageQueue.put(:name => 'head', :message => created.to_yaml, :priority => 10, :ttr => 60)
  end

  def bucket_object(file_path)
    "#{message[:hash_key]}/"+input_file(file_path)
  end

  def mgf_filename
    # Review the contents of the directory, listing number of .mgf files that were found
    @mgf_filename ||= Dir["#{UNPACK_DIR}/*.mgf"].first
  end
  
  def mgf_filenames
    # Review the contents of the directory, listing number of .mgf files that were found
    @mgf_filenames ||= Dir["#{UNPACK_DIR}/mgfs/*.mgf"]
  end

end
  