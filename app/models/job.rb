class Job < ActiveRecord::Base

  include Utilities

  before_create :set_defaults

  has_many :chunks, :dependent => :destroy, :order => 'filename'
  
  has_attached_file :mgf, :path => ":rails_root/public/jobs/:id_partition/:basename.:extension"
  validates_attachment_presence :mgf, :message => "^MGF file is required"

  validates_presence_of :name, :message => "^Name is required"
  validates_presence_of :searcher, :message => "^Search method is required"
  validates_presence_of :parameter_file_id, :message => "^Parameter file is required"
  validates_presence_of :spectra_count, :message => "^Spectra count is required"
  validates_presence_of :priority, :message => "^Priority is required"
  validates_numericality_of :spectra_count, :message => "^Spectra count is not a number"

  after_destroy :remove_s3_files, :remove_s3_working_folder

  class << self

    # pagination
    
    def page(page=1, limit=10)
      paginate(:page => page,
               :order => 'created_at DESC',
               :per_page => limit
      )
    end

    # find jobs that aren't complete

    def incomplete
      find(:all, :conditions => ["status != ?", "Complete"])
    end
  end

  # check if we're packing, and that we started it more than 10 minutes ago

  def stuck_packing?
    packing? && started_pack_at < 10.minutes.ago.to_f
  end

  # check if any chunks are stuck
  # if incomplete is empty, nothing can be stuck
  # and if we have any, and the last one we finish was more than 10 minutes ago, we're stuck
  # TODO: need to deal with something having a higher priority, since it would make the job appear to be stuck

  def stuck_chunks?
    return false if chunks.incomplete.empty? #if all the chunks are complete, we can't have stuck ones
    chunk = chunks.complete.first(:order => 'finished_at DESC')
    if chunk
      chunk.finished_at < 10.minutes.ago.to_f
    else
      false
    end
  end

  # send the process messages for the stuck chunks

  def resend_stuck_chunks
    chunks.incomplete.each do |chunk|
      chunk.send_process_message
    end
  end

  def minimum_chunk_time
    min = chunks.minimum('finished_at-started_at').to_f
    (min < 0) ? 0 : min
    rescue
      0
  end

  def maximum_chunk_time
    chunks.maximum('finished_at-started_at').to_f
    rescue
      0
  end

  def average_chunk_time
    ave = chunks.average('finished_at-started_at')
    (ave < 0) ? 0 : ave
    rescue
      0
  end

  def processing_time
    start = chunks.minimum('started_at')
    finish = chunks.maximum('finished_at')
    finish-start
    rescue
      0
  end

  def remove_s3_files
    Aws.delete_object(s3_results_key) && Aws.delete_object(datafile)
  end

  def s3_results_key
    "completed-jobs/#{output_file}"
  end

  def remove_s3_working_folder
    Aws.delete_folder("#{hash_key}")
  end
  
  def set_defaults
    self.status = "Pending"
    self.created_at = Time.now
    self.datafile = "pending-jobs/#{zipfile_name}"
    self.hash_key = Digest::SHA1.hexdigest(self.object_id.to_s+self.created_at.to_s)
  end

  def upload_manifest
    send_verified_data("#{hash_key}/manifest.yml", output_files.to_yaml, md5_item(output_files.to_yaml, false), {})
  end

  def output_files
    remote_file_list("#{hash_key}/out")
  end

  def packing?
    ((status == "Packing") || (status == "Requested packing"))
  end

  def pending?
    status == "Pending"
  end

  def complete?
    status == "Complete"
  end

  def processed?
    existing_finished = chunks.inject(true) {|working, chunk| working && chunk.finished? }
    matching_counts = (chunks.size == chunks.first.chunk_count)
    (existing_finished && matching_counts)
  end

  def launch
    self.status = "Launching" #remove the launch link
    self.launched_at = Time.now.to_f
    self.save
    send_background_upload_message
  end

  def background_s3_upload
    parameter_file = load_parameter_file
    create_parameter_textfile(parameter_file)
    bundle_datafile
    upload_datafile_to_s3
    send_message(UNPACK)
  end

  def load_parameter_file
    parameter_file = nil
    case searcher
      when "omssa"
        parameter_file = OmssaParameterFile.find(parameter_file_id)
      when "tandem"
        parameter_file = TandemParameterFile.find(parameter_file_id)
    end
    parameter_file
  end

  def search_database
    load_parameter_file.database.match(/^(.+)\.fasta$/)[1]
  end

  def create_parameter_textfile(parameter_file)
    parameter_file.write_file(local_datafile_directory)
  end

  def send_pack_request
    upload_manifest
    self.started_pack_at = Time.now.to_f
    self.status = "Requested packing" #remove the launch link
    self.save!
    send_message(PACK)
  end

  def output_file
    output = datafile.split('/').last.match(/(.+)\.zip$/)[1]
    output+"-results.zip"
  end

  def send_background_upload_message
    hash = {:type => BACKGROUNDUPLOAD, :job_id => id}
    MessageQueue.put(:name => 'head', :message => hash.to_yaml, :priority => 50, :ttr => 600)
  end

  def send_message(type)
    hash = {:type => type, :bucket_name => Aws.bucket_name, :job_id => id, :hash_key => hash_key, :datafile => datafile, :output_file => output_file, :searcher => searcher, :search_database => search_database, :spectra_count => spectra_count, :priority => priority}
    MessageQueue.put(:name => 'node', :message => hash.to_yaml, :priority => 50, :ttr => 600)
  end

  def bundle_datafile
    File.delete(local_zipfile) if File.exist?(local_zipfile) #avoid the already added file exception
    Zip::ZipFile.open(local_zipfile, Zip::ZipFile::CREATE) { |zipfile|
      zipfile.add(mgf_file_name, local_datafile_directory+mgf_file_name)
      zipfile.add(PARAMETER_FILENAME, local_datafile_directory+PARAMETER_FILENAME)
    }
  end

  def upload_datafile_to_s3
    send_file("pending-jobs/#{zipfile_name}", local_zipfile)
  end
  
  def zipfile_name
    "#{name}.zip"
  end
  
  def local_zipfile
    @local_zipfile ||= File.join(local_datafile_directory, zipfile_name)
  end

  def local_datafile_directory
    File.join(RAILS_ROOT, "/public/jobs/#{id_partition}/")
  end
  
  def id_partition
    ("%09d" % id).scan(/\d{3}/).join("/")
  end

end
