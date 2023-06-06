class Car < ApplicationRecord
  # include IdentityCache

  Kaminari::Hooks.init if defined?(Kaminari::Hooks)
  Elasticsearch::Model::Response::Response.__send__ :include, Elasticsearch::Model::Response::Pagination::Kaminari

  include Rails.application.routes.url_helpers

  extend FriendlyId

  include Searchable

  paginates_per 12

  acts_as_taggable_on :options

  acts_as_paranoid

  friendly_id :slug_candidates, use: [:slugged, :finders]
  has_one_attached :exclusive_thumb, dependent: :destroy

  def slug_candidates
    [
      # :display_name
        [:display_name, :id],
        [:display_name, :manufacture_year, :id],
        [:display_name, :mileage, :id]
    ]
  end

  with_options inverse_of: :car do
    belongs_to :body_type, inverse_of: :cars, counter_cache: :cars_count
    belongs_to :fuel_type, inverse_of: :cars, counter_cache: :cars_count
    belongs_to :model, counter_cache: :cars_count, inverse_of: :cars
    belongs_to :brand, touch: true, counter_cache: :cars_count, inverse_of: :cars
    belongs_to :transmission_type, inverse_of: :cars, counter_cache: :cars_count
    has_many :car_medias, inverse_of: :car
    has_many :shortleazze

    has_many :car_images, -> { where('file_type LIKE ?', '%image%') }, class_name: 'CarMedia', inverse_of: :car
  end

  after_destroy :cleanup_media

  has_many :appointment_requests, dependent: :nullify

  has_and_belongs_to_many :top_ten_lists

  enum nap: ['n', 'j']
  enum reserved: {'Gereserveerd' => 'j', 'Niet Gereserveerd' => 'n'}
  enum new: {'Nieuw' => 'j', 'Occasion' => 'n'}
  enum btw_marge: {'BTW' => 'B', 'Marge' => 'M'}

  scope :car_includes, -> { joins(:brand, :model, :body_type, :fuel_type, :transmission_type, :car_medias, :options) }

  scope :week_old, -> { where('cars.created_at >= ?', 1.week.ago.utc).limit(30) }

  scope :active, -> { where(active: true) }

  scope :similar_in_price_range, -> (reference_car, margin) { price_range = {min: reference_car.price_month * (1 - margin), max: reference_car.price_month * (1 + margin)}; where('price_month > :min AND price_month < :max', min: price_range[:min], max: price_range[:max]) }

  validates_associated :model, :brand
  validates :mileage, :color, :engine_size, :manufacture_year, presence: true
  # validates :video_url, format: URI::regexp(%w[http https])
# 
  #caching
  # cache_has_many :car_medias, embed: true
  # cache_has_many :car_images, embed: true

  def main_image
    # fetch_car_images.try(:first)
    car_images.try(:first)
  end

  def make_current_images_undestroyable
    car_images.update_all(keep_record: true)
  end

  def cleanup_media
    car_medias.destroyable.destroy_all
  end

  def latest_car_images
    last_date = car_images.with_deleted.order('created_at desc').limit(1).first
    car_images.with_deleted.where('DATE(created_at) = DATE(:date)', date: last_date.created_at)
  end

  def display_name
    fields = [self.brand.name, self.model.name]
    fields << self.car_type unless self.car_type.blank?
    fields.join(' ')
  end

  def name
    fields = []
    fields << self.car_type unless self.car_type.blank?
    fields.join(' ')
  end

  def related_cars(amount = 3)
    # if option_list.any?
    #   car_obj = Car.distinct.active.joins(:car_images, :brand, :model, :fuel_type).order(created_at: :desc)
    #   cars = car_obj.tagged_with(option_list, any: true, :order_by_matching_tag_count => true, brand: self.brand).where.not(id: self.id)
    #   cars = cars.similar_in_price_range(self, 0.2) if cars.size > amount
    #   cars = cars.where(brand: brand) if cars.size > amount
    #   cars.where(model: model) if cars.size > amount
    #   cars.limit(amount)
    # else
    #   cars = car_obj.similar_in_price_range(self, 0.2)
    #   cars.where(brand: brand, model: model).limit(amount)
    # end
  end

  def as_indexed_json(options = {})
    as_json(
        only: [:id, :display_name, :mileage, :color, :engine_size, :type, :nap, :rdw, :price_total, :price_50_50, :price_month, :manufacture_year, :cylinders, :engine_power, :top_speed, :interior, :energy_label, :road_tax, :door_count, :energy_label],
        include: [:model, :brand, :body_type, :fuel_type, :transmission_type, :options],
        methods: [:display_name]
    )
  end

  def share_on_facebook
    post = FacebookPost.new_from_car(self)
    post.scheduled_at = Time.now + 10.minutes
    post.save
  end

  def self.parse_cardesk_parameters(params, car = nil)
    # puts "===params=======#{params.inspect}========"
    brand = Brand.find_or_create_by(name: params[:merk])
    model = Model.find_or_create_by(name: params[:model], brand: brand)
    body = BodyType.find_or_create_by(name: params[:carrosserie])
    fuel = FuelType.find_or_create_by(name: params[:brandstof])
    transmission = TransmissionType.find_or_create_by(name: params[:transmissie])

    options = params[:zoekaccessoires]['accessoire']
    # opmerkingen = params[:opmerkingen].split("Bijzonderheden:").last

    return {
        vin: params[:vin],
        aantal_zitplaatsen: params[:aantal_zitplaatsen],
        vehicle_number: params[:voertuignr],
        vehicle_number_hexon: params[:voertuignr_hexon],
        brand_id: brand.id,
        model_id: model.id,
        transmission_type_id: transmission.id,
        body_type_id: body.id,
        fuel_type_id: fuel.id,
        mileage: params[:tellerstand],
        color: params[:basiskleur],
        color_type: params[:laksoort],
        engine_size: params[:cilinder_inhoud],
        car_type: params[:type],
        nap: params[:nap_weblabel],
        price_total: params[:verkoopprijs_particulier],
        price_month: (params[:lease]['maandbedrag'] rescue nil),
        price_50_50: params[:verkoopprijs_handel],
        price_discount: params[:actieprijs],
        manufacture_year: params[:bouwjaar],
        cylinders: params[:cilinder_aantal],
        engine_power: params[:vermogen_motor_pk],
        top_speed: params[:topsnelheid],
        energy_label: params[:energielabel],
        road_tax: "#{params[:wegenbelasting_kwartaal_min]} / #{params[:wegenbelasting_kwartaal_max]}",
        reserved: params[:gereserveerd],
        new: params[:nieuw],
        btw_marge: params[:btw_marge],
        door_count: params[:aantal_deuren],
        license_plate: params[:kenteken],
        option_list: options,
        interior: params[:bekleding],
        # comment: opmerkingen,
        best_day_deal: true
    }
  end

  def display_price_total
    helper.format_money(price_total)
  end

  def display_price_month
    helper.format_money(price_month)
  end

  def display_price_50_50
    helper.format_money(price_50_50)
  end

  def self.collection_to_google_adword_csv(cars)
    CSV.generate do |csv|
      csv << ['ID', 'ID2', 'Item title', 'Final URL', 'Image URL', 'Item subtitle', 'Item description', 'Item category', 'Price', 'Sale price', 'Contextual keywords', 'Item address', 'Tracking template', 'Custom parameter']
      cars.each do |car|
        begin
          csv << [car.id, car.vehicle_number, "#{car.brand.name} #{car.model.name}", Rails.application.routes.url_helpers.car_url(car), car.main_image.try(:file).try(:url), car.car_type, car.comment, car.body_type.try(:name), "#{car.price_total.to_i} EUR", "#{car.price_month.to_i} EUR", nil, nil, nil, nil]
        rescue Exception => e
          Rails.logger.info "Exporting to adwords csv for car with id: #{car.id} has failed due to this error: #{e.message}"
        end
      end
    end
  end

  def self.collection_to_facebook_product_feed_xml(cars)
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.feed(xmlns: 'http://www.w3.org/2005/Atom', 'xmlns:g' => 'http://base.google.com/ns/1.0') do
        xml.title 'HAM FB Car Feed'
        xml.link(rel: 'self', href: 'https://hollandiaautomotive.nl')
        cars.each { |car| car.to_facebook_product_xml(xml) }
      end
    end
    builder.to_xml
  end

  def to_facebook_product_xml(xml)
    xml.entry do
      xml[:g].id vehicle_number_hexon
      xml[:g].title display_name
      xml[:g].description "#{display_name} - #{comment}"
      xml[:g].link Rails.application.routes.url_helpers.car_url(self)
      xml[:g].image_link main_image.file.url
      xml[:g].brand brand.try(:name)
      xml[:g].condition 'used'
      xml[:g].availability 'in stock'
      xml[:g].price "EUR #{price_month}"
      xml[:g].google_product_category '916 - Vehicles & Parts > Vehicles > Motor Vehicles > Cars, Trucks & Vans'
    end
  end

  def self.color_options
    Car.all.pluck(:color).uniq.sort.map(&:capitalize)
  end

  def self.door_count_options
    Car.all.pluck(:door_count).compact.uniq.sort
  end

  def self.energy_label_options
    Car.all.pluck(:energy_label).compact.uniq.sort
  end

  private

  def self.download_video(url)
    urls = ViddlRb.get_urls(url.gsub('http://', 'https://'))
    carmedia = CarMedia.new
    carmedia.remote_file_url = urls.first
    carmedia.save!
    carmedia
  end

  def helper
    @helper ||= Class.new do
      include ActionView::Helpers::NumberHelper
      include ApplicationHelper
    end.new
  end

  def self.current_month_cars_count
    Car.distinct.active.joins(:car_images, :brand, :model, :fuel_type).where('cars.created_at > ?', Time.now.beginning_of_month).count
  end
end
