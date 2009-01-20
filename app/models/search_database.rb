class SearchDatabase < ActiveRecord::Base

  validates_presence_of :name, :message => "^Name is required"
  validates_presence_of :keyword, :message => "^Keyword is required"
  validates_presence_of :version, :message => "^Version file is required"

  has_attached_file :search_database, :path => ":rails_root/public/search_databases/:id_partition/:basename.:extension"
  validates_attachment_presence :search_database, :message => "^Search database file is required"

  class << self
    # pagination
    def page(page=1, limit=10)
      paginate(:page => page,
               :order => 'created_at DESC',
               :per_page => limit
      )
    end
  end

end