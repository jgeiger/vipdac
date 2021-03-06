require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "/jobs/index.html.erb" do
  include JobsHelper
  
  before(:each) do
    @chunks = mock("chunks", :pending => [], :working => [], :complete => [], :empty? => true, :size => 0)

    @jobs = []
    @datafile = mock("datafile", :uploaded_file_name => "uploaded.mgf")
    
    0.upto(2) do |i|
      job = mock_model(Job)
      job.stub!(:chunks).and_return(@chunks)
      job.stub!(:status).and_return("pending")
      job.stub!(:searcher).and_return("tandem")
      job.stub!(:link).and_return("website")
      job.stub!(:launched_at).and_return(Time.now.to_f)
      job.stub!(:finished_at).and_return(Time.now.to_f)
      job.stub!(:datafile).and_return(@datafile)
      job.stub!(:processing_time).and_return(100.0)
      job.stub!(:maximum_chunk_time).and_return(100.0)
      job.stub!(:minimum_chunk_time).and_return(100.0)
      job.stub!(:average_chunk_time).and_return(100.0)
      job.stub!(:name).and_return("name")
      job.stub!(:spectra_count).and_return(200)
      job.stub!(:priority).and_return(200)
      job.stub!(:complete?).and_return(false)
      job.stub!(:statistics_sent).and_return(false)

      @jobs << job
    end 

    @jobs.stub!(:size).and_return(2)
    @jobs.stub!(:total_pages).and_return(1)
    assigns[:jobs] = @jobs
  end

  it "should render list of jobs" do
    render "/jobs/index.html.erb"
  end
end

