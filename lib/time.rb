module DataScript
  class TimeUtilities

    SECONDS = 1
    MINUTES = 60 * SECONDS
    HOURS = 60 * MINUTES
    DAYS = 24 * HOURS
    MONTHS = 30 * DAYS
    YEARS = 365.25 * DAYS

    def self.pretty(time=0)
      if (time >= YEARS)
        "#{(time / YEARS).to_i} years"
      elsif (time >= MONTHS)
        "#{(time / MONTHS).to_i} months"
      elsif (time >= DAYS)
        "#{(time / DAYS).to_i} days"
      elsif (time >= HOURS)
        "#{(time / HOURS).to_i} hours"
      elsif (time >= MINUTES)
        min = (time / MINUTES).to_i
        sec = ( (time - (min * MINUTES)) / SECONDS ).to_i
        "#{min} minutes #{sec} seconds"
      elsif (time >= SECONDS)
        "#{(time / SECONDS).to_i} seconds"
      else
        'Immediately'
      end
    end
  end
end
