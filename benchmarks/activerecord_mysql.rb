require 'bundler/setup'

require 'active_record'
require 'benchmark/ips'
require 'json'

TIME    = (ENV['BENCHMARK_TIME'] || 5).to_i
RECORDS = (ENV['BENCHMARK_RECORDS'] || TIME*10).to_i

conn = { adapter: 'mysql2', database: 'railsperf_standalone' }

ActiveRecord::Base.establish_connection(conn)
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :name, :email
    t.timestamps null: false
  end

  create_table :exhibits, force: true do |t|
    t.belongs_to :user
    t.string :name
    t.text :notes
    t.timestamps null: false
  end
end

class User < ActiveRecord::Base
  has_many :exhibits
end

class Exhibit < ActiveRecord::Base
  belongs_to :user

  def look; attributes end
  def feel; look; user.name end

  def self.with_name
    where("name IS NOT NULL")
  end

  def self.with_notes
    where("notes IS NOT NULL")
  end

  def self.look(exhibits) exhibits.each(&:look) end
  def self.feel(exhibits) exhibits.each(&:feel) end
end

module ActiveRecord
  class Faker
    LOREM = %Q{Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse non aliquet diam. Curabitur vel urna metus, quis malesuada elit.
     Integer consequat tincidunt felis. Etiam non erat dolor. Vivamus imperdiet nibh sit amet diam eleifend id posuere diam malesuada. Mauris at accumsan sem.
     Donec id lorem neque. Fusce erat lorem, ornare eu congue vitae, malesuada quis neque. Maecenas vel urna a velit pretium fermentum. Donec tortor enim,
     tempor venenatis egestas a, tempor sed ipsum. Ut arcu justo, faucibus non imperdiet ac, interdum at diam. Pellentesque ipsum enim, venenatis ut iaculis vitae,
     varius vitae sem. Sed rutrum quam ac elit euismod bibendum. Donec ultricies ultricies magna, at lacinia libero mollis aliquam. Sed ac arcu in tortor elementum
     tincidunt vel interdum sem. Curabitur eget erat arcu. Praesent eget eros leo. Nam magna enim, sollicitudin vehicula scelerisque in, vulputate ut libero.
     Praesent varius tincidunt commodo}.split

    def self.name
      LOREM.grep(/^\w*$/).sort_by { rand }.first(2).join ' '
    end

    def self.email
      LOREM.grep(/^\w*$/).sort_by { rand }.first(2).join('@') + ".com"
    end
  end
end

# pre-compute the insert statements and fake data compilation,
# so the benchmarks below show the actual runtime for the execute
# method, minus the setup steps

# Using the same paragraph for all exhibits because it is very slow
# to generate unique paragraphs for all exhibits.
notes = ActiveRecord::Faker::LOREM.join ' '
today = Date.today

# puts "Inserting #{RECORDS} users and exhibits..."
RECORDS.times do |record|
  user = User.create!(
    created_at: today,
    name: ActiveRecord::Faker.name,
    email: ActiveRecord::Faker.email
  )

  Exhibit.create!(
    created_at: today,
    name: ActiveRecord::Faker.name,
    user: user,
    notes: notes
  )
end

report = Benchmark.ips(TIME, quiet: true) do |x|
  ar_obj       = Exhibit.find(1)
  attrs        = { name: 'sam' }
  attrs_first  = { name: 'sam' }
  attrs_second = { name: 'tom' }
  exhibit      = {
    name: ActiveRecord::Faker.name,
    notes: notes,
    created_at: Date.today
  }

  x.report 'Model.new (instantiation)' do
    Exhibit.new
  end

  x.report 'Model.new (setting attributes)' do
    Exhibit.new(attrs)
  end

  x.report 'Model.first' do
    Exhibit.first
  end

  x.report("Model.all limit(100)") do
    Exhibit.look Exhibit.limit(100)
  end

  x.report("Model.all first(100)") do
    Exhibit.look Exhibit.first(100)
  end

  # x.report "Model.all limit(100) with relationship" do
  #   Exhibit.feel Exhibit.limit(100).includes(:user)
  # end

  x.report "Model.all limit(10,000)" do
    Exhibit.look Exhibit.limit(10000)
  end

  x.report 'Model.named_scope' do
    Exhibit.limit(10).with_name.with_notes
  end

  x.report 'Model.create' do
    Exhibit.create(exhibit)
  end

  x.report 'Resource#update' do
    model = Exhibit.first
    if model.respond_to?(:update)
      Exhibit.first.update(name: 'bob')
    else
      Exhibit.first.update_attributes(name: 'bob')
    end
  end

  x.report 'Model.find(id)' do
    User.find(1)
  end
end

stats = {
  component: :active_record,
  version: ActiveRecord::VERSION::STRING,
  entries: report.entries.map { |e|
    {
      label: e.label,
      iterations: e.iterations,
      ips: e.ips,
      ips_sd: e.ips_sd
    }
  }
}

puts stats.to_json