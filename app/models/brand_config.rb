class BrandConfig < ActiveRecord::Base
  include BrandableCSS

  self.primary_key = 'md5'
  serialize :variables, Hash

  attr_accessible :variables

  validates :variables, presence: true
  validates :md5, length: {is: 32}

  before_validation :generate_md5
  before_update do
    raise 'BrandConfigs are a key-value mapping of config variables and an md5 digest '\
          'of those variables, so they are immutable. You do not update them, you just '\
          'save a new one and it will generate the new md5 for you'
  end

  has_many :accounts, foreign_key: 'brand_config_md5'

  def generate_md5
    self.id = Digest::MD5.hexdigest(self.variables.to_s)
  end

  def get_value(variable_name)
    self.variables[variable_name]
  end

  def to_scss
    "// This file is autogenerated by brand_config.rb as a result of running `rake brand_configs:write`\n" +
    variables.map do |name, value|
      next unless (config = BrandableCSS.variables_map[name])
      value = %{url("#{value}")} if config['type'] == 'image'
      "$#{name}: #{value};"
    end.compact.join("\n")
  end

  def filename
    File.join(CONFIG['paths']['branded_scss_folder'], md5, '_brand_variables.scss')
  end

  def public_folder
    "dist/brandable_css/#{md5}"
  end

  def save_file!
    logger.info "saving BrandConfig: #{filename}"
    FileUtils.mkdir_p(File.dirname(filename))
    File.write(filename, to_scss)
  end

  def compile_css!
    BrandableCSS.compile_brand!(md5)
  end

  def sync_to_s3!
    Canvas::CDN.push_to_s3!(public_folder) if Canvas::CDN.enabled?
  end

  def save_and_sync_to_s3!
    save_file!
    compile_css!
    sync_to_s3!
  end

  def self.clean_up_unused
    BrandConfig.
      where('NOT EXISTS (SELECT 1 FROM accounts WHERE brand_config_md5=brand_configs.md5)').
      where('NOT share').
      destroy_all
  end

end