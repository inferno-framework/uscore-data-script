require 'date'

module DataScript
  class Constraints

    CONSTRAINTS = {
      'one_male' => lambda {|results| results.any? {|bundle| patient(bundle) && gender(bundle) == 'male'}},
      'one_female' => lambda {|results| results.any? {|bundle| gender(bundle) == 'female'}},
      'one_child' => lambda {|results| results.any? {|bundle| age = age(bundle); age >= 0 && age < 18 }},
      'child_has_immunizations' => lambda {|results| results.any? {|bundle| age = age(bundle); (age >= 0 && age < 18) && has(bundle, FHIR::Immunization) }},
      'child_does_not_smoke' => lambda {|results| results.any? {|bundle| age = age(bundle); (age >= 0 && age < 18) && !smoker(bundle) }},
      'one_adult' => lambda {|results| results.any? {|bundle| age = age(bundle); age >= 18 && age <= 65  }},
      'one_elder' => lambda {|results| results.any? {|bundle| age = age(bundle); age > 65 }},
      'elder_has_device' => lambda {|results| results.any? {|bundle| age = age(bundle); (age > 65) && has(bundle, FHIR::Device) }},
      'elder_is_alive' => lambda {|results| results.any? {|bundle| age = age(bundle); (age > 65) && alive(bundle) }},
      'one_white' => lambda {|results| results.any? {|bundle| race(bundle) == 'White'}},
      'one_black' => lambda {|results| results.any? {|bundle| race(bundle) == 'Black or African American'}},
      'one_hispanic' => lambda {|results| results.any? {|bundle| ethnicity(bundle) == 'Hispanic or Latino'}},
      'one_smoker' => lambda {|results| results.any? {|bundle| smoker(bundle) }},
      'one_organization' => lambda {|results| results.any? {|bundle| has(bundle, FHIR::Organization) }},
      'one_practitioner' => lambda {|results| results.any? {|bundle| has(bundle, FHIR::Practitioner) }},
      'observation_code' => lambda {|results| results.any? {|bundle| bundle.entry.any? {|entry| entry.resource.resourceType == 'Observation' && !entry.resource.valueCodeableConcept.nil?} }},
      'observation_quantity' => lambda {|results| results.any? {|bundle| bundle.entry.any? {|entry| entry.resource.resourceType == 'Observation' && !entry.resource.valueQuantity.nil?} }},
      'observation_string' => lambda {|results| results.any? {|bundle| bundle.entry.any? {|entry| entry.resource.resourceType == 'Observation' && !entry.resource.valueString.nil?} }}
    }

    CONSTRAINTS_MRBURNS = {
      'has_allergy' => lambda {|results| results.any? {|bundle| has(bundle, FHIR::AllergyIntolerance) }},
      'has_pulse_ox' => lambda {|results| results.any? {|bundle| has_pulse_ox(bundle) }},
    }

    CONSTRAINTS_MRBURNS_DOES_NOT_NEED = [
      'one_female',
      'one_child',
      'child_has_immunizations',
      'child_does_not_smoke',
      'one_adult',
      'elder_is_alive',
      'one_white',
      'one_black',
      'one_hispanic',
      'one_smoker',
    ]

    REQUIRED_PROFILES = [
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-allergyintolerance',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-careplan',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-careteam',
      #'http://hl7.org/fhir/us/core/StructureDefinition/us-core-condition',
      'http://hl7.org/fhir/us/core//StructureDefinition/us-core-condition-encounter-diagnosis',
      'http://hl7.org/fhir/us/core//StructureDefinition/us-core-condition-problems-health-concerns',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-implantable-device',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-documentreference',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-encounter',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-goal',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-immunization',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-location',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-medicationrequest',
      # observations listed at end...
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-organization',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-practitioner',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-practitionerrole',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-procedure',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-provenance',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-questionnaireresponse',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-relatedperson',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-servicerequest',
      # US Core Observation profiles...
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-clinical-test',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-imaging',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-sexual-orientation',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-social-history',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-survey',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-sdoh-assessment',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-smokingstatus',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-vital-signs',
      'http://hl7.org/fhir/us/core/StructureDefinition/head-occipital-frontal-circumference-percentile',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-blood-pressure', #'http://hl7.org/fhir/StructureDefinition/bp'
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-bmi', #'http://hl7.org/fhir/StructureDefinition/bmi',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-body-height', #'http://hl7.org/fhir/StructureDefinition/bodyheight',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-body-temperature', #'http://hl7.org/fhir/StructureDefinition/bodytemp',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-body-weight', #'http://hl7.org/fhir/StructureDefinition/bodyweight',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-head-circumference',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-heart-rate', #'http://hl7.org/fhir/StructureDefinition/heartrate',
      'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-bmi-for-age',
      'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-weight-for-height',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry',
      'http://hl7.org/fhir/us/core/StructureDefinition/us-core-respiratory-rate' #'http://hl7.org/fhir/StructureDefinition/resprate',
    ]

    attr_accessor :violations

    def initialize
      @violations = []
    end

    def satisfied?(results, keys = CONSTRAINTS.keys)
      @violations.clear
      constraints = CONSTRAINTS.keep_if {|key, test| keys.include?(key)}
      constraints.each do |key, test|
        test_result = test.call(results)
        unless test_result
          @violations << key
        end
      end
      @violations.empty?
    end

    def profiles_present(results)
      present = results.map {|b| b.entry.map {|e| e.resource&.meta&.profile }}.flatten.uniq
      present.delete(nil)
      present
    end

    def self.patient(bundle)
      bundle.entry.each do |entry|
        return entry.resource if entry.resource.is_a?(FHIR::Patient)
      end
      nil
    end

    def self.gender(bundle)
      self.patient(bundle)&.gender
    end

    def self.age(bundle)
      birth_date = self.patient(bundle)&.birthDate
      return -Float::INFINITY if birth_date.nil?
      date = Date.parse(birth_date)
      age = Date.today.year - date.year
      age -= 1 if Date.today < date.next_year(age)
      age
    end

    def self.alive(bundle)
      p = self.patient(bundle)
      ((p&.deceasedBoolean.nil? || p&.deceasedBoolean == false) && p&.deceasedDateTime.nil?)
    end

    def self.race(bundle)
      self.patient(bundle)&.us_core_race&.ombCategory&.display rescue nil
    end

    def self.ethnicity(bundle)
      self.patient(bundle)&.us_core_ethnicity&.ombCategory&.display rescue nil
    end

    def self.smoker(bundle)
      entries = bundle.entry.select {|entry| entry.resource.is_a?(FHIR::Observation)}
      observations = entries.map {|entry| entry.resource}
      smoking_statuses = observations.select {|observation| observation.code.text&.start_with?('Tobacco smoking status')}
      altA = smoking_statuses.map {|status| status.value.text}.include? 'Current every day smoker'
      altB = smoking_statuses.map {|status| status.value.text}.include? 'Smokes tobacco daily (finding)'
      (altA || altB)
    end

    def self.has(bundle, fhir_class)
      bundle.entry.any? {|entry| entry.resource.is_a?(fhir_class)}
    end

    def self.has_pulse_ox(bundle)
      bundle.entry.any? do |entry|
        entry.resource&.meta&.profile&.include? 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry'
      end
    end

    def self.has_headcircum(results)
      results.any? do |bundle|
        bundle.entry.any? do |entry|
          entry.resource&.meta&.profile&.include? 'http://hl7.org/fhir/us/core/StructureDefinition/head-occipital-frontal-circumference-percentile'
        end
      end
    end
  end
end
