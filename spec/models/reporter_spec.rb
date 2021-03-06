require File.dirname(__FILE__) + '/../spec_helper'

describe Reporter do

  before(:each) do
    @reporter = create_reporter
  end

  describe "check for stuck jobs" do
    it "should find all incomplete jobs" do
      Job.should_receive(:incomplete).and_return([])
      @reporter.check_for_stuck_jobs
    end

    describe "given an incomplete job" do
      describe "with stuck chunks" do
        it "should send process messages for all non finished chunks" do
          j1 = mock_model(Job)
          j1.should_receive(:stuck_chunks?).and_return(true)
          j1.should_receive(:priority=).with(50).and_return(true)
          j1.should_receive(:save!).and_return(true)
          j1.should_receive(:resend_stuck_chunks).and_return(true)
          j2 = mock_model(Job)
          j2.should_receive(:stuck_chunks?).and_return(false)
          j2.should_receive(:stuck_packing?).and_return(false)
          jobs = [j1, j2]
          Job.should_receive(:incomplete).and_return(jobs)
          @reporter.check_for_stuck_jobs
        end
      end
      describe "with stuck packing" do
        it "should send process messages for all non finished chunks" do
          j1 = mock_model(Job)
          j1.should_receive(:stuck_chunks?).and_return(false)
          j1.should_receive(:stuck_packing?).and_return(false)
          j2 = mock_model(Job)
          j2.should_receive(:stuck_chunks?).and_return(false)
          j2.should_receive(:stuck_packing?).and_return(true)
          j2.should_receive(:send_pack_request)
          jobs = [j1, j2]
          Job.should_receive(:incomplete).and_return(jobs)
          @reporter.check_for_stuck_jobs
        end
      end
    end
  end

  describe "process head message" do
    before(:each) do
      @report = mock("report")
      @message = mock("message")
      @reporter.should_receive(:build_report).with(@message).and_return(@report)
    end

    after(:each) do
      @reporter.process_head_message(@message)
    end

    describe "unknown message" do
      it "should update the chunk and check the status" do
        @report.should_receive(:[]).with(:type).and_return("cheese")
        @message.should_receive(:delete).and_return(true)
      end
    end

    describe "created message" do
      it "should create a chunk in the database" do
        @report.should_receive(:[]).with(:type).and_return(CREATED)
        @reporter.should_receive(:update_chunk).with(@report, @message, true).and_return(true)
      end
    end

    describe "background upload message" do
      it "should upload the job datafile" do
        @report.should_receive(:[]).with(:type).and_return(BACKGROUNDUPLOAD)
        @reporter.should_receive(:background_upload).with(@report, @message).and_return(true)
      end
    end

    describe "process search database message" do
      it "should process the search database" do
        @report.should_receive(:[]).with(:type).and_return(PROCESSDATABASE)
        @reporter.should_receive(:process_search_database).with(@report, @message).and_return(true)
      end
    end

    describe "send statistics message" do
      it "should have the job send the statistics to vipstats" do
        @report.should_receive(:[]).with(:type).and_return(SENDSTATISTICS)
        @reporter.should_receive(:statistics_to_vipstats).with(@report, @message).and_return(true)
      end
    end

    describe "process datafile message" do
      it "should process the search database" do
        @report.should_receive(:[]).with(:type).and_return(PROCESSDATAFILE)
        @reporter.should_receive(:process_datafile).with(@report, @message).and_return(true)
      end
    end

    describe "unpacking message" do
      it "should set the job status to unpacking" do
        @report.should_receive(:[]).with(:type).and_return(JOBUNPACKING)
        @reporter.should_receive(:job_status).with(@report, @message, "Unpacking").and_return(true)
      end
    end

    describe "unpacked message" do
      it "should set the job status to unpacked" do
        @report.should_receive(:[]).with(:type).and_return(JOBUNPACKED)
        @reporter.should_receive(:job_status).with(@report, @message, "Processing").and_return(true)
      end
    end

    describe "packing message" do
      it "should set the job status to packing" do
        @report.should_receive(:[]).with(:type).and_return(JOBPACKING)
        @reporter.should_receive(:job_status).with(@report, @message, "Packing").and_return(true)
      end
    end

    describe "packed message" do
      it "should set the job status to packed" do
        @report.should_receive(:[]).with(:type).and_return(JOBPACKED)
        @reporter.should_receive(:set_job_complete).with(@report, @message).and_return(true)
      end
    end

    describe "start message" do
      it "should update the chunk" do
        @report.should_receive(:[]).with(:type).and_return(START)
        @reporter.should_receive(:update_chunk).with(@report, @message).and_return(true)
      end
    end

    describe "finish message" do
      it "should update the chunk and check the status" do
        @report.should_receive(:[]).with(:type).and_return(FINISH)
        @reporter.should_receive(:update_chunk).with(@report, @message).and_return(true)
        @reporter.should_receive(:check_job_status).with(@report).and_return(true)
      end
    end
  end

  describe "process loop" do
    it "should set the started time" do
      Time.stub!(:now).and_return(1.0)
      @reporter.should_receive(:process).and_return(true)
      @reporter.process_loop(false)
      @reporter.started.should == 1.0
    end

    it "should complete the steps" do
      @reporter.should_receive(:process).and_return(true)
      @reporter.process_loop(false)
    end
  end

  describe "process" do
    describe "with head message" do
      describe "with exceptions" do
        it "should fail getting the message" do
          MessageQueue.should_receive(:get).with(:name => 'head', :peek => true).and_raise(Exception)
          HoptoadNotifier.should_receive(:notify).with({:error_message=>"Exception: Exception", :request=>{:params=>nil}, :error_class=>"Exception"}).and_return(true)
          @reporter.process
        end

        it "should exit on SignalException errors" do
          HoptoadNotifier.should_not_receive(:notify)
          MessageQueue.should_receive(:get).with(:name => 'head', :peek => true).and_raise(SignalException.new("TERM"))
          @reporter.should_receive(:exit).and_return(true)
          @reporter.process
        end

        it "should exit on Interrupt errors" do
          HoptoadNotifier.should_not_receive(:notify)
          MessageQueue.should_receive(:get).with(:name => 'head', :peek => true).and_raise(Interrupt.new("EXIT"))
          @reporter.should_receive(:exit).and_return(true)
          @reporter.process
        end

        it "should fail processing the message" do
          MessageQueue.should_receive(:get).with(:name => 'head', :peek => true).and_return("headmessage")
          @reporter.should_receive(:process_head_message).with("headmessage").and_raise(Exception)
          HoptoadNotifier.should_receive(:notify).with({:error_message=>"Exception: Exception", :request=>{:params=>"headmessage"}, :error_class=>"Exception"}).and_return(true)
          @reporter.process
        end

        it "should fail checking for chunks" do
          MessageQueue.should_receive(:get).with(:name => 'head', :peek => true).and_return("headmessage")
          @reporter.should_receive(:process_head_message).with("headmessage").and_return(true)
          @reporter.should_receive(:minute_ago?).and_return(true)
          @reporter.should_receive(:check_for_stuck_jobs).and_raise(Exception)
          HoptoadNotifier.should_receive(:notify).with({:error_message=>"Exception: Exception", :request=>{:params=>"headmessage"}, :error_class=>"Exception"}).and_return(true)
          @reporter.process
        end
      end

      describe "less than a minute" do
        it "should complete the steps" do
          MessageQueue.should_receive(:get).with(:name => 'head', :peek => true).and_return("headmessage")
          @reporter.should_receive(:process_head_message).with("headmessage").and_return(true)
          @reporter.should_not_receive(:check_for_stuck_jobs)
          @reporter.should_receive(:minute_ago?).and_return(false)
          @reporter.process_loop(false)
          @reporter.started.should be_instance_of(Time)
        end
      end

      describe "more than a minute" do
        it "should complete the steps" do
          MessageQueue.should_receive(:get).with(:name => 'head', :peek => true).and_return("headmessage")
          @reporter.should_receive(:process_head_message).with("headmessage").and_return(true)
          @reporter.should_receive(:check_for_stuck_jobs).and_return(true)
          @reporter.should_receive(:minute_ago?).and_return(true)
          @reporter.process_loop(false)
          @reporter.started.should be_instance_of(Time)
        end
      end
    end

    describe "with no message" do
      describe "less than a minute" do
        it "should complete the steps" do
          MessageQueue.should_receive(:get).with(:name => 'head', :peek => true).and_return(nil)
          @reporter.should_receive(:sleep).with(1).and_return(true)
          @reporter.should_receive(:minute_ago?).and_return(false)
          @reporter.should_not_receive(:check_for_stuck_jobs)
          @reporter.process_loop(false)
          @reporter.started.should be_instance_of(Time)
        end
      end
      
      describe "more than a minute" do
        it "should complete the steps" do
          MessageQueue.should_receive(:get).with(:name => 'head', :peek => true).and_return(nil)
          @reporter.should_receive(:sleep).with(1).and_return(true)
          @reporter.should_receive(:minute_ago?).and_return(true)
          @reporter.should_receive(:check_for_stuck_jobs).and_return(true)
          @reporter.process_loop(false)
          @reporter.started.should be_instance_of(Time)
        end
      end
    end
  end
  
  describe "minute_ago?" do
    it "should return false if now less than 1 minute ago" do
      time_now = Time.now
      Time.stub!(:now).and_return(time_now)
      @reporter.started = time_now
      @reporter.minute_ago?.should be_false
      @reporter.started.should be_instance_of(Time)
    end

    it "should return true if now more than 1 minute ago" do
      time_then = 5.minutes.ago
      time_now = Time.now
      Time.stub!(:now).and_return(time_now)
      @reporter.started = time_then
      @reporter.minute_ago?.should be_true
      @reporter.started.should be_instance_of(Time)
    end
  end
  
  describe "run" do
    before(:each) do
      @node = mock_model(Node)
      Aws.should_receive(:instance_type).and_return("type")
      Aws.should_receive(:instance_id).and_return("id")
    end

    it "should complete the steps with a new node" do
      @node.should_receive(:save).and_return(true)
      Node.should_receive(:new).with(:instance_type => "type", :instance_id => "id").and_return(@node)
      @reporter.should_receive(:write_pid).and_return(true)
      @reporter.should_receive(:process_loop).and_return(true)
      @reporter.run
    end

    it "should complete the steps with an existing node" do
      @node.should_receive(:save).and_return(false)
      Node.should_receive(:new).with(:instance_type => "type", :instance_id => "id").and_return(@node)
      @reporter.should_receive(:write_pid).and_return(true)
      @reporter.should_receive(:process_loop).and_return(true)
      @reporter.run
    end
  end

  describe "build report" do
    it "should return a hash parsed by YAML" do
      message = mock("message")
      message.should_receive(:body).and_return("--- :thing:thing")
      YAML.should_receive(:load).with("--- :thing:thing").and_return({:thing => "thing"})
      @reporter.build_report(message).should == {:thing => "thing"}
    end
  end

  describe "write pid" do
    it "should write the current process id to a file" do
      File.should_receive(:join).and_return("reporter.pid")
      file = mock("file")
      file.should_receive(:puts).with($$).and_return(true)
      File.should_receive(:open).with("reporter.pid", "w").and_yield(file)
      @reporter.write_pid
    end
  end

  describe "load job" do
    it "should load a job with the id" do
      @job = mock_model(Job)
      Job.stub!(:find).and_return(@job)
      job = @reporter.load_job("id")
      job.should == @job
    end

    it "should log an exception if the job doesn't exist" do
      HoptoadNotifier.should_receive(:notify).with({:request=>{:params=>"id"}, :error_message=>"Job Load Error: Exception", :error_class=>"Invalid Job"}).and_return(true)
      Job.stub!(:find).and_raise(Exception)
      job = @reporter.load_job("id")
      job.should be_nil
    end
  end

  describe "load search database" do
    it "should load a search_database with the id" do
      @search_database = mock_model(SearchDatabase)
      SearchDatabase.stub!(:find).and_return(@search_database)
      search_database = @reporter.load_search_database("id")
      search_database.should == @search_database
    end

    it "should log an exception if the search_database doesn't exist" do
      HoptoadNotifier.should_receive(:notify).with({:request=>{:params=>"id"}, :error_message=>"Search Database Load Error: Exception", :error_class=>"Invalid Search Database"}).and_return(true)
      SearchDatabase.stub!(:find).and_raise(Exception)
      search_database = @reporter.load_search_database("id")
      search_database.should be_nil
    end
  end

  describe "load datafile" do
    it "should load a datafile with the id" do
      @datafile = mock_model(Datafile)
      Datafile.stub!(:find).and_return(@datafile)
      datafile = @reporter.load_datafile("id")
      datafile.should == @datafile
    end

    it "should log an exception if the datafile doesn't exist" do
      HoptoadNotifier.should_receive(:notify).with({:request=>{:params=>"id"}, :error_message=>"Datafile Load Error: Exception", :error_class=>"Invalid Datafile"}).and_return(true)
      Datafile.stub!(:find).and_raise(Exception)
      datafile = @reporter.load_datafile("id")
      datafile.should be_nil
    end
  end
  
  describe "check job status" do
    before(:each) do
      @report = mock("report")
      @report.should_receive(:[]).with(:job_id).and_return(1234)
      @job = mock_model(Job)
    end

    describe "processed and not complete" do
      it "should update the job status and send a pack request" do
        @reporter.should_receive(:load_job).with(1234).and_return(@job)
        @job.should_receive(:processed?).and_return(true)
        @job.should_receive(:complete?).and_return(false)
        @job.should_receive(:send_pack_request).and_return(true)
        @reporter.check_job_status(@report)
      end
    end

    describe "don't send message if not processed" do
      it "should not be processed" do
        @reporter.should_receive(:load_job).with(1234).and_return(@job)
        @job.should_receive(:processed?).and_return(false)
        @job.should_not_receive(:send_pack_request).and_return(true)
        @reporter.check_job_status(@report)
      end
    end

    describe "don't send message if already complete" do
      it "should not be complete" do
        @reporter.should_receive(:load_job).with(1234).and_return(@job)
        @job.should_receive(:processed?).and_return(true)
        @job.should_receive(:complete?).and_return(true)
        @job.should_not_receive(:send_pack_request).and_return(true)
        @reporter.check_job_status(@report)
      end
    end

    describe "don't send message if nil" do
      it "should not be processed" do
        @reporter.should_receive(:load_job).with(1234).and_return(nil)
        @job.should_not_receive(:processed?)
        @job.should_not_receive(:complete?)
        @job.should_not_receive(:save)
        @job.should_not_receive(:send_pack_request)
        @reporter.check_job_status(@report)
      end
    end
  end

  describe "set job complete" do
    before(:each) do
      @report = mock("report")
      @report.should_receive(:[]).with(:job_id).and_return(1234)
      @message = mock("message")
      @job = mock_model(Job)
      @resultfile = mock_model(Resultfile)
      Time.stub!(:now).and_return(1)
    end

    describe "success" do
      it "should have a valid job link" do
        @reporter.should_receive(:load_job).with(1234).and_return(@job)
        @job.should_receive(:resultfile_name).and_return("resultfile")
        @reporter.should_receive(:create_resultfile_link).with(@report, @job).and_return("link")

        Resultfile.should_receive(:new).with({:link=>"link", :name=>"resultfile"}).and_return(@resultfile)
        @resultfile.should_receive(:save!).and_return(true)
        @resultfile.should_receive(:persist).and_return(true)

        @job.should_receive(:status=).with("Complete").and_return(true)
        @job.should_receive(:finished_at=).with(1.0).and_return(true)
        @job.should_receive(:save!).and_return(true)

        @job.should_receive(:remove_s3_working_folder).and_return(true)
        @message.should_receive(:delete).and_return(true)
        @reporter.set_job_complete(@report, @message)
      end
    end

    describe "failure" do
      it "should not set a link and delete the message" do
        @job.should_not_receive(:save!)
        @job.should_not_receive(:remove_s3_working_folder)
        @message.should_receive(:delete).and_return(true)
        @reporter.should_receive(:load_job).with(1234).and_return(nil)
        @reporter.set_job_complete(@report, @message)
      end
    end
  end

  describe "create result file link" do
    it "should return a string with the s3 link" do
      report = mock("report")
      report.should_receive(:[]).with(:bucket_name).and_return("bucket_name")
      job = mock_model(Job)
      job.should_receive(:resultfile_name).and_return("outputfile")
      @reporter.create_resultfile_link(report, job).should == "http://s3.amazonaws.com/bucket_name/resultfiles/outputfile.zip"
    end
  end

  describe "update chunk" do
    before(:each) do
      @chunk = mock_model(Chunk)
      @message = mock("message")
      Chunk.should_receive(:reporter_chunk).with("report").and_return(@chunk)
    end

    describe "success for create" do
      it "should create a chunk and send the process message" do
        @chunk.should_receive(:save!).and_return(true)
        @chunk.should_receive(:send_process_message).and_return(true)
        @message.should_receive(:delete).and_return(true)
        @reporter.update_chunk("report", @message, true)
      end
    end

    describe "success for update" do
      it "should update a chunk" do
        @chunk.should_receive(:save!).and_return(true)
        @chunk.should_not_receive(:send_process_message).and_return(true)
        @message.should_receive(:delete).and_return(true)
        @reporter.update_chunk("report", @message)
      end
    end
  end

  describe "job status" do
    describe "success" do
      it "should update the status of the job" do
        @job = mock_model(Job)
        @job.should_receive(:status=).and_return(true)
        @message = mock("message")
        @report = mock("report")
        @report.should_receive(:[]).with(:job_id).and_return(1234)
        @reporter.should_receive(:load_job).with(1234).and_return(@job)

        @job.should_receive(:save!).and_return(true)
        @message.should_receive(:delete).and_return(true)
        @reporter.job_status(@report, @message, "status")
      end
    end

    describe "failure" do
      it "should delete the message if the job doesn't exist" do
        @job = mock_model(Job)
        @message = mock("message")
        @report = mock("report")
        @report.should_receive(:[]).with(:job_id).and_return(1234)
        @reporter.should_receive(:load_job).with(1234).and_return(nil)
        @job.should_not_receive(:save!)
        @job.should_not_receive(:status=)
        @message.should_receive(:delete).and_return(true)
        @reporter.job_status(@report, @message, "status")
      end
    end
  end

  describe "background upload" do
    before(:each) do
      @job = mock_model(Job)
      @message = mock("message")
      @report = mock("report")
      @report.should_receive(:[]).with(:job_id).and_return(1234)
      @message.should_receive(:delete).and_return(true)
    end

    describe "success" do
      it "should update the status of the job" do
        @job.should_receive(:status=).with("Uploading").and_return(true)
        @reporter.should_receive(:load_job).with(1234).and_return(@job)
        @job.should_receive(:save!).and_return(true)
        @job.should_receive(:background_s3_upload).and_return(true)
        @reporter.background_upload(@report, @message)
      end
    end

    describe "failure" do
      it "should delete the message if the job doesn't exist" do
        @reporter.should_receive(:load_job).with(1234).and_return(nil)
        @job.should_not_receive(:save!)
        @job.should_not_receive(:status=)
        @job.should_not_receive(:background_s3_upload)
        @reporter.background_upload(@report, @message)
      end
    end
  end

  describe "statistics to vipstats" do
    before(:each) do
      @job = mock_model(Job)
      @message = mock("message")
      @report = mock("report")
      @report.should_receive(:[]).with(:job_id).and_return(1234)
      @message.should_receive(:delete).and_return(true)
    end

    describe "success" do
      it "should update the status of the job" do
        @reporter.should_receive(:load_job).with(1234).and_return(@job)
        @job.should_receive(:submit_to_vipstats).and_return(true)
        @reporter.statistics_to_vipstats(@report, @message)
      end
    end

    describe "failure" do
      it "should delete the message if the job doesn't exist" do
        @reporter.should_receive(:load_job).with(1234).and_return(nil)
        @job.should_not_receive(:submit_to_vipstats)
        @reporter.statistics_to_vipstats(@report, @message)
      end
    end
  end

  describe "process search database" do
    before(:each) do
      @search_database = mock_model(SearchDatabase)
      @message = mock("message")
      @report = mock("report")
      @report.should_receive(:[]).with(:database_id).and_return(1234)
      @message.should_receive(:delete).and_return(true)
    end

    describe "success" do
      it "should process the search database" do
        @reporter.should_receive(:load_search_database).with(1234).and_return(@search_database)
        @search_database.should_receive(:process_and_upload).and_return(true)
        @reporter.process_search_database(@report, @message)
      end
    end

    describe "failure" do
      it "should delete the message if the search_database doesn't exist" do
        @reporter.should_receive(:load_search_database).with(1234).and_return(nil)
        @search_database.should_not_receive(:process_and_upload)
        @reporter.process_search_database(@report, @message)
      end
    end
  end

  describe "process datafile" do
    before(:each) do
      @datafile = mock_model(Datafile)
      @message = mock("message")
      @report = mock("report")
      @report.should_receive(:[]).with(:datafile_id).and_return(1234)
      @message.should_receive(:delete).and_return(true)
    end

    describe "success" do
      it "should process the datafile" do
        @reporter.should_receive(:load_datafile).with(1234).and_return(@datafile)
        @datafile.should_receive(:process_and_upload).and_return(true)
        @reporter.process_datafile(@report, @message)
      end
    end

    describe "failure" do
      it "should delete the message if the datafile doesn't exist" do
        @reporter.should_receive(:load_datafile).with(1234).and_return(nil)
        @datafile.should_not_receive(:process_and_upload)
        @reporter.process_datafile(@report, @message)
      end
    end
  end

  protected
    def create_reporter
      record = Reporter.new
      record
    end

end
