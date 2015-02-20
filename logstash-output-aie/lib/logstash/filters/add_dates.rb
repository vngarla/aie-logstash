# add_dates filter
#
# This filter will add month_t, day_t, and hour_t dates to the event.  
# This simplifies timeseries analyses with these granularities 

require "logstash/filters/base"
require "logstash/namespace"
require "set"

#     
class LogStash::Filters::AddDates < LogStash::Filters::Base
  config_name "add_dates"
  plugin_status 0
  
  # input field
  config :field, :validate => :string, :default => "@timestamp"
  # timezone for conversion
  config :timezone, :validate => :string, :require => false
  # month output field
  config :target_month, :validate  => :string, :default => "month_t"
  # day output field
  config :target_day, :validate  => :string, :default => "day_t"
  # hour output field
  config :target_hour, :validate  => :string, :default => "hour_t"
  #
  public
  def register
    require "java"  
  end # def register
  public
  def initialize(config = {})
    super
	@tz = @timezone && !@timezone.empty ? java.util.TimeZone::get_time_zone(@timezone) : java.util.TimeZone::get_default()
	@UTC = java.util.TimeZone::get_time_zone("UTC")
    @threadsafe = true
  end # def initialize
  # add the date to the specified field
  private 
  def add_date(event, cal, target)
	target_cal = java.util.Calendar::get_instance()
	target_cal.clear()
	target_cal.set_time_zone(@UTC)
	target_cal.set(java.util.Calendar::YEAR, cal.get(java.util.Calendar::YEAR))
	target_cal.set(java.util.Calendar::MONTH, cal.get(java.util.Calendar::MONTH))
	if(target == @target_day || target == @target_hour)
		target_cal.set(java.util.Calendar::DAY_OF_MONTH, cal.get(java.util.Calendar::DAY_OF_MONTH))
	end
	if(target == @target_hour)
		target_cal.set(java.util.Calendar::HOUR_OF_DAY, cal.get(java.util.Calendar::HOUR_OF_DAY))
	end
	epochmillis = target_cal.get_time_in_millis()
	event[target] = Time.at(epochmillis / 1000).utc
  end #add_date
  #
  public
  def filter(event)
	return unless filter?(event)
	return event unless event.include?(@field)
	timestamp = event[@field]
	if(! (timestamp.kind_of? Time) )
		@logger.warn("not a Time", :field => @field, :timestamp => timestamp)
		return event
	end
	# convert timestamp to calendar, set timezone to local timezone
	cal = java.util.Calendar::get_instance()
	cal.set_time_in_millis(timestamp.to_i * 1000)
	cal.set_time_zone(@tz)
	add_date(event, cal, @target_month) unless @target_month.empty? 
	add_date(event, cal, @target_day) unless @target_day.empty? 
	add_date(event, cal, @target_hour) unless @target_hour.empty? 
	return event
  end # def filter

end # class LogStash::Filters::Date