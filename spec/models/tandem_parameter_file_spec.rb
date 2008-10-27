require File.dirname(__FILE__) + '/../spec_helper'

describe TandemParameterFile do
  before(:each) do
    @parameter_file = create_tandem_parameter_file
  end

  describe "create" do
    [:name, :taxon].each do |key|
      it "should not create a new instance without '#{key}'" do
        create_tandem_parameter_file(key => nil).should_not be_valid
      end
    end
  end

  describe "associations" do
    [:tandem_modifications].each do |key|
      it "should respond to '#{key}'" do
        create_tandem_parameter_file.respond_to?(key).should be_true
      end
    end
  end

  describe "validations" do
    it "should require a unique name" do
      @parameter_file.save
      duplicate = create_tandem_parameter_file
      duplicate.should_not be_valid
    end

    it "should require at least two ions" do
      @parameter_file.should_not be_valid
      @parameter_file.b_ion = true
      @parameter_file.should be_valid
    end
  end

  describe "when loading the taxonomies" do
    it "should return an empty array for an exception" do
      File.stub!(:open).and_raise("error")
      TandemParameterFile.taxonomies.should == []
    end

    it "should return an empty array for an empty file" do
      text = mock("filetext", :readlines => [])
      File.stub!(:open).and_return(text)
      TandemParameterFile.taxonomies.should == []
    end

    it "should return an array" do
      text = mock("filetext", :readlines => ['<taxon label="human_uni">','<taxon label="human_ipi">'])
      File.stub!(:open).and_return(text)
      TandemParameterFile.taxonomies.should == ["human_uni", "human_ipi"]
    end
  end
  
  describe "ions" do
    it "should return [] for no selected ions" do
      @parameter_file.a_ion = false
      @parameter_file.ions.should == []
    end

    it "should return [true,true] for 2 selected ions" do
      @parameter_file.b_ion = true
      @parameter_file.ions.should == [true, true]
    end
  end
  
  describe "ion_names" do
    it "should return '' for no selected ions" do
      @parameter_file.a_ion = false
      @parameter_file.ion_names.should == ''
    end

    it "should return 'A-ions B-ions' for 2 selected ions" do
      @parameter_file.b_ion = true
      @parameter_file.ion_names.should == "A-ions B-ions"
    end
  end

  describe "ion_xml" do
    it "should not have a yes for all ions false" do
      @parameter_file = create_tandem_parameter_file(:a_ion => false, :b_ion => false, :c_ion => false, :x_ion => false, :y_ion => false, :z_ion => false)
      @parameter_file.ion_xml.should_not match(/yes<\/note>/)
    end
    it "should not have a no for all ions true" do
      @parameter_file = create_tandem_parameter_file(:a_ion => true, :b_ion => true, :c_ion => true, :x_ion => true, :y_ion => true, :z_ion => true)
      @parameter_file.ion_xml.should_not match(/no<\/note>/)
    end
  end

  describe "mass_xml" do
    it "should return empty string for no modifications" do
      @parameter_file.mass_xml.should == ""
    end

    it "should return empty string for no mass modifications" do
      @mod1 = mock_model(TandemModification)
      @mod1.should_receive(:mass_string).once.and_return(nil)
      @parameter_file.should_receive(:tandem_modifications).twice.and_return([@mod1])
      @parameter_file.mass_xml.should == ""
    end

    it "should return return the mass string for a single modification" do
      @mod1 = mock_model(TandemModification)
      @mod1.should_receive(:mass_string).twice.and_return("10.0@A")
      @parameter_file.should_receive(:tandem_modifications).twice.and_return([@mod1])
      @parameter_file.mass_xml.should match(/10.0@A/)
    end

    it "should return return the mass string for multiple modifications" do
      @mod1 = mock_model(TandemModification)
      @mod1.should_receive(:mass_string).twice.and_return("10.0@A")
      @mod2 = mock_model(TandemModification)
      @mod2.should_receive(:mass_string).twice.and_return("20.0@B")
      @parameter_file.should_receive(:tandem_modifications).twice.and_return([@mod1, @mod2])
      @parameter_file.mass_xml.should match(/10.0@A,20.0@B/)
    end

    it "should return return the mass string for multiple modifications excluding nil values" do
      @mod1 = mock_model(TandemModification)
      @mod1.should_receive(:mass_string).twice.and_return("10.0@A")
      @mod2 = mock_model(TandemModification)
      @mod2.should_receive(:mass_string).once.and_return(nil)
      @mod3 = mock_model(TandemModification)
      @mod3.should_receive(:mass_string).twice.and_return("20.0@B")
      @parameter_file.should_receive(:tandem_modifications).twice.and_return([@mod1, @mod2, @mod3])
      @parameter_file.mass_xml.should match(/10.0@A,20.0@B/)
    end
  end

  describe "motif_xml" do
    it "should return empty string for no modifications" do
      @parameter_file.motif_xml.should == ""
    end

    it "should return empty string for no motif modifications" do
      @mod1 = mock_model(TandemModification)
      @mod1.should_receive(:motif_string).once.and_return(nil)
      @parameter_file.should_receive(:tandem_modifications).twice.and_return([@mod1])
      @parameter_file.motif_xml.should == ""
    end

    it "should return return the motif string for a single modification" do
      @mod1 = mock_model(TandemModification)
      @mod1.should_receive(:motif_string).twice.and_return("10.0@[ST!]{P}")
      @parameter_file.should_receive(:tandem_modifications).twice.and_return([@mod1])
      @parameter_file.motif_xml.should == %Q(<note type="input" label="residue, potential modification motif">10.0@[ST!]{P}</note>)
    end

    it "should return return the motif string for multiple modifications" do
      @mod1 = mock_model(TandemModification)
      @mod1.should_receive(:motif_string).twice.and_return("10.0@[ST!]{P}")
      @mod2 = mock_model(TandemModification)
      @mod2.should_receive(:motif_string).twice.and_return("20.0@[SX!]{X}")
      @parameter_file.should_receive(:tandem_modifications).twice.and_return([@mod1, @mod2])
      @parameter_file.motif_xml.should == %Q(<note type="input" label="residue, potential modification motif">10.0@[ST!]{P},20.0@[SX!]{X}</note>)
    end

    it "should return return the motif string for multiple modifications excluding nil values" do
      @mod1 = mock_model(TandemModification)
      @mod1.should_receive(:motif_string).twice.and_return("10.0@[ST!]{P}")
      @mod2 = mock_model(TandemModification)
      @mod2.should_receive(:motif_string).once.and_return(nil)
      @mod3 = mock_model(TandemModification)
      @mod3.should_receive(:motif_string).twice.and_return("20.0@[SX!]{X}")
      @parameter_file.should_receive(:tandem_modifications).twice.and_return([@mod1, @mod2, @mod3])
      @parameter_file.motif_xml.should == %Q(<note type="input" label="residue, potential modification motif">10.0@[ST!]{P},20.0@[SX!]{X}</note>)
    end
  end

  describe "string functions" do
    it "should return a valid xml string for taxon_xml" do
      @parameter_file.taxon_xml.should match(/taxon">human_ipi/)
    end
    it "should return a valid xml string for enzyme_xml" do
      @parameter_file.enzyme = "enz"
      @parameter_file.enzyme_xml.should match(/cleavage site">enz/)
    end
    it "should return a valid xml string for n_terminal_xml" do
      @parameter_file.n_terminal = "12"
      @parameter_file.n_terminal_xml.should match(/N-terminal mass change">12/)
    end
    it "should return a valid xml string for c_terminal_xml" do
      @parameter_file.c_terminal = "1234"
      @parameter_file.c_terminal_xml.should match(/C-terminal mass change">1234/)
    end
  end

  describe "writing the parameter file" do
    it "should create a file with the name" do
      @file = mock("file")
      @file.should_receive(:puts).and_return(true)
      File.should_receive(:open).with("jobdir/parameters.conf", "w").once.and_yield(@file)
      @parameter_file.write_file("jobdir/")
    end
  end

  describe "page" do
    it "should call paginate" do
      TandemParameterFile.should_receive(:paginate).with({:page => 2, :order => 'name', :per_page => 20}).and_return(true)
      TandemParameterFile.page(2,20)
    end
  end

  describe "modification attributes" do
    before(:each) do
      @array = ["one", "two"]
    end

    it "should respond to the request" do
      @parameter_file.should_receive(:modification_attributes=).with(@array).and_return(true)
      @parameter_file.modification_attributes=(@array)
    end

    it "should build tandem modifications for each attribute" do
      tandem_modifications = mock("modifications")
      tandem_modifications.should_receive(:build).with("one").and_return(true)
      tandem_modifications.should_receive(:build).with("two").and_return(true)
      @parameter_file.should_receive(:tandem_modifications).twice.and_return(tandem_modifications)
      @parameter_file.modification_attributes=(@array)
    end
  end

  protected
    def create_tandem_parameter_file(options = {})
      record = TandemParameterFile.new({ :name => "jobname", :taxon => "human_ipi", :enzyme => "enzyme", :a_ion => true }.merge(options))
      record
    end

end
