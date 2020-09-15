require 'base64'
require 'securerandom'
require_relative 'constraints'
require 'fhir_models'
require 'time'

module DataScript
  class Modifications
    def self.modify!(results)
      FHIR.logger.level = :info
      # results is an Array of FHIR::Bundle objects,
      # where the first resource is a Patient.

      # Remove unwanted patient extensions and identifers
      results.each do |bundle|
        # first, remove unwanted patient extensions
        bundle.entry.first.resource.extension.delete_if do |extension|
          extension.url.start_with? 'http://synthetichealth.github.io'
        end

        # next, remove unwanted patient identifier
        bundle.entry.first.resource.identifier.delete_if do |identifier|
          identifier.system.start_with? 'http://standardhealthrecord.org'
        end

        # make sure every patient has a postalCode
        # some towns do not have postalCodes
        bundle.entry.first.resource.address.first.postalCode = '01999' unless bundle.entry.first.resource.address.first.postalCode

        # finally, make sure every patient has an address period
        bundle.entry.first.resource.address.first.period = FHIR::Period.new
        bundle.entry.first.resource.address.first.period.start = bundle.entry.first.resource.birthDate
      end

      # Add discharge disposition to first encounter of each record
      results.each do |bundle|
        encounter_entry = bundle.entry.find { |e| e.resource.resourceType == 'Encounter' }
        encounter = encounter_entry.resource
        encounter.hospitalization = FHIR::Encounter::Hospitalization.new
        encounter.hospitalization.dischargeDisposition = create_codeable_concept('http://www.nubc.org/patient-discharge','01','Discharged to home care or self care (routine discharge)')
      end

      # create vitalspanel
      panel_members = [
        'http://hl7.org/fhir/StructureDefinition/resprate',
        'http://hl7.org/fhir/StructureDefinition/heartrate',
        'http://hl7.org/fhir/StructureDefinition/oxygensat',
        'http://hl7.org/fhir/StructureDefinition/bodytemp',
        'http://hl7.org/fhir/StructureDefinition/bodyheight',
        'http://hl7.org/fhir/StructureDefinition/headcircum',
        'http://hl7.org/fhir/StructureDefinition/bodyweight',
        'http://hl7.org/fhir/StructureDefinition/bmi',
        'http://hl7.org/fhir/StructureDefinition/bp'
      ]
      new_vitalspanels = 0
      results.each do |bundle|
        # find the provenance for this bundle
        provenance = bundle.entry.find { |e| e.resource.resourceType == 'Provenance' }
        # get all the encounters
        encounters = bundle.entry.select { |e| e.resource.resourceType == 'Encounter' }
        # get all the observations
        observations = bundle.entry.select { |e| e.resource.resourceType == 'Observation' }
        # add a vitalspanel to each encounter where appropriate
        encounters.each do |entry|
          encounter_url = entry.fullUrl
          obs = observations.select {|e| e.resource.encounter.reference == encounter_url}
          vitals = obs.select {|e| e.resource.meta && (e.resource.meta.profile & panel_members).any?}
          if vitals && !vitals.empty?
            # create a vitalspanel
            vitalspanel = FHIR::Observation.new
            vitalspanel.id = SecureRandom.uuid
            vitalspanel.status = 'final'
            vitalspanel.meta = FHIR::Meta.new
            vitalspanel.meta.profile = [ 'http://hl7.org/fhir/StructureDefinition/vitalspanel', 'http://hl7.org/fhir/StructureDefinition/vitalsigns' ]
            vitalspanel.category = vitals.first.resource.category
            vitalspanel.code = create_codeable_concept('http://loinc.org','85353-1','Vital signs, weight, height, head circumference, oxygen saturation and BMI panel')
            vitalspanel.effectiveDateTime = vitals.first.resource.effectiveDateTime
            vitalspanel.encounter = vitals.first.resource.encounter
            vitalspanel.issued = vitals.first.resource.issued
            vitalspanel.subject = vitals.first.resource.subject
            vitalspanel.hasMember = []
            vitals.each do |member|
              reference = FHIR::Reference.new
              reference.reference = member.fullUrl
              reference.display = member.resource.code.text
              vitalspanel.hasMember << reference
            end
            # create an entry
            bundle.entry << create_bundle_entry(vitalspanel)
            # add the new vitalspanel to the provenance resource
            if provenance
              provenance.resource.target << FHIR::Reference.new
              provenance.resource.target.last.reference = "urn:uuid:#{vitalspanel.id}"
            end
            new_vitalspanels += 1
          end
        end
      end
      puts "  - Created #{new_vitalspanels} vitalspanels"

      # Make sure at least one organization has an NPI
      organization_entry = results.last.entry.find { |e| e.resource.resourceType == 'Organization' }
      organization = organization_entry.resource
      # Add a 10 digit NPI
      organization.identifier << FHIR::Identifier.new
      organization.identifier.last.system = 'http://hl7.org/fhir/sid/us-npi'
      organization.identifier.last.value = '9999999999'
      # Add a CLIA
      organization.identifier << FHIR::Identifier.new
      organization.identifier.last.system = 'urn:oid:2.16.840.1.113883.4.7'
      organization.identifier.last.value = '9999999999'

      # Add a PractitionerRole.endpoint
      pr_entry = results.last.entry.find { |e| e.resource.resourceType == 'PractitionerRole' }
      pr = pr_entry.resource
      pr.endpoint = [ FHIR::Reference.new ]
      pr.endpoint.first.reference = '#endpoint'
      pr.endpoint.first.type = 'Endpoint'
      endpoint = FHIR::Endpoint.new
      endpoint.id = 'endpoint'
      endpoint.status = 'active'
      endpoint.connectionType = create_codeable_concept('http://terminology.hl7.org/CodeSystem/endpoint-connection-type', 'direct-project', 'Direct Project').coding.first
      endpoint.payloadType = [ create_codeable_concept('http://terminology.hl7.org/CodeSystem/endpoint-payload-type', 'any', 'Any') ]
      endpoint.address = "mailto:#{pr.telecom.last.value}"
      pr.contained = [endpoint]

      # select by smoking status
      selection_smoker = results.find {|b| DataScript::Constraints.smoker(b)}
      unless selection_smoker
        # if there is no smoker, choose the oldest patient
        # and make them start smoking at the end of their life...
        # because why not?
        oldest = results.sort {|a,b| a.entry.first.resource.birthDate <=> b.entry.first.resource.birthDate }.first
        alter_smoking_status(oldest)
        puts "  - Altered Smoker:     #{oldest.entry.first.resource.id}"
      end

      # sort the results by number of Conditions
      results.sort do |a,b|
        count_a = a.entry.count {|e| e.resource.resourceType == 'Condition'}
        count_b = b.entry.count {|e| e.resource.resourceType == 'Condition'}
        count_a <=> count_b
      end
      # select the person with the most Conditions
      selection_conditions = results.last
      alter_condition(selection_conditions)
      puts "  - Altered Condition:  #{selection_conditions.entry.first.resource.id}"

      # select someone with the most numerous gender
      # from the people remaining, and remove their name
      unless MRBURNS
        selection_name = pick_by_gender(results)
        remove_name(selection_name)
        puts "  - Altered Name:       #{selection_name.entry.first.resource.id}"
      end

      # select by clinical note
      selection_note = results.find {|b| DataScript::Constraints.has(b, FHIR::DocumentReference)}
      if selection_note
        # modify it to have a URL rather than base64 encoded data
        docref = selection_note.entry.reverse.find {|e| e.resource.resourceType == 'DocumentReference' }.resource
        report = selection_note.entry.reverse.find {|e|
          e.resource.resourceType == 'DiagnosticReport' &&
          e.resource.presentedForm.first.data == docref.content.first.attachment.data }.resource
        url = 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'
        docref.content.first.attachment.contentType = 'application/pdf'
        docref.content.first.attachment.data = nil
        docref.content.first.attachment.url = url
        report.presentedForm.first.contentType = 'application/pdf'
        report.presentedForm.first.data = nil
        report.presentedForm.first.url = url
        puts "  - Altered DocumentReference URL: #{docref.id}"
        puts "  - Altered DiagnosticReport  URL: #{report.id}"
      else
        puts "  * FAILED to find DocumentReference!"
      end

      # collect all the clinical notes and modify codes so we have at least one of each type
      category_types = [
        [ 'Cardiology', 'LP29708-2' ],
        [ 'Pathology', 'LP7839-6' ],
        [ 'Radiology', 'LP29684-5' ]
      ]
      note_types = [
        [ 'Consultation note', '11488-4' ],
        [ 'Discharge summary', '18842-5' ],
        [ 'History and physical note', '34117-2' ],
        [ 'Procedure note', '28570-0' ],
        [ 'Progress note', '11506-3' ],
        [ 'Referral note', '57133-1' ],
        [ 'Surgical operation note', '11504-8' ],
        [ 'Nurse Note', '34746-8' ]
      ]
      category_types.map! {|type| create_codeable_concept('http://loinc.org',type.last,type.first) }
      note_types.map! {|type| create_codeable_concept('http://loinc.org',type.last,type.first) }
      # grab all the clinical notes
      all_docref = results.map {|b| b.entry.select {|e| e.resource.resourceType == 'DocumentReference'}.map {|e| e.resource} }.flatten
      all_report = results.map {|b| b.entry.select {|e| e.resource.resourceType == 'DiagnosticReport'}.map {|e| e.resource} }.flatten
      # there are more DiagnosticReports than DocumentReferences,
      # so we need to filter them...
      docref_data = all_docref.map {|r| r.content.first.attachment.data}
      matching_report = all_report.select { |r| r.presentedForm.length >= 1 && docref_data.include?(r.presentedForm.first.data) }
      # need to replace the codes...
      # we will use a uniform distribution of note_types
      note_types_index = 0
      category_types_index = 0
      all_docref.zip(matching_report).each do |docref, report|
        docref.type = note_types[note_types_index]
        report.category = [ category_types[category_types_index] ]
        report.code = note_types[note_types_index]
        note_types_index += 1
        category_types_index += 1
        note_types_index = 0 if note_types_index >= note_types.length
        category_types_index = 0 if category_types_index >= category_types.length
      end
      puts "  - Altered codes for #{all_docref.length} clinical notes."

      all_docref.each do |docref|
        docref&.identifier&.each {|id| id.value = "urn:uuid:#{id.value}" if (id.system == 'urn:ietf:rfc:3986' && !id.value&.start_with?('urn'))}
      end
      puts "  - Altered identifiers for #{all_docref.length} clinical notes."

      # select by medication
      selection_medication = results.find {|b| DataScript::Constraints.has(b, FHIR::Medication)}
      unless selection_medication
        # if there is no free-standing Medication resource, we need to make one.
        med_bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::MedicationRequest) }
        medreq = med_bundle.entry.find { |e| e.resource.resourceType == 'MedicationRequest' }
        provenance = med_bundle.entry.find { |e| e.resource.resourceType == 'Provenance' }
        # create the medication
        med = FHIR::Medication.new
        med.id = SecureRandom.uuid
        med.status = 'active'
        med.meta = FHIR::Meta.new
        med.meta.profile = [ 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication' ]
        med.code = medreq.resource.medicationCodeableConcept
        # alter the MedicationRequest to refer to the Medication resource and not a code
        medreq.resource.reportedBoolean = true
        medreq.resource.medicationCodeableConcept = nil
        medreq.resource.medicationReference = FHIR::Reference.new
        medreq.resource.medicationReference.reference = "urn:uuid:#{med.id}"
        medreq.resource.status = 'active'
        # add the Medication as a new Bundle entry
        med_bundle.entry << create_bundle_entry(med)
        # add the Medication into the provenance
        provenance.resource.target << FHIR::Reference.new
        provenance.resource.target.last.reference = "urn:uuid:#{med.id}"
        puts "  - Altered Medication: #{med_bundle.entry.first.resource.id}"
      end

      # select by device
      selection_device = results.find {|b| DataScript::Constraints.has(b, FHIR::Device)}
      if selection_device
        # if there is a Device resource, we need to clone it and use carrierAIDC.
        device = selection_device.entry.find { |e| e.resource.resourceType == 'Device' }
        provenance = selection_device.entry.find { |e| e.resource.resourceType == 'Provenance' }
        # create the new Device
        dev = FHIR::Device.new(device.resource.to_hash)
        dev.id = SecureRandom.uuid
        dev.udiCarrier.first.carrierHRF = nil
        barcode_file_path = File.join(File.dirname(__FILE__), './barcode.png')
        barcode_file = File.open(barcode_file_path, 'rb')
        barcode_data = barcode_file.read
        barcode_file.close
        dev.udiCarrier.first.carrierAIDC = Base64.encode64(barcode_data)
        # add the Device as a new Bundle entry
        selection_device.entry << create_bundle_entry(dev)
        # add the Device into the provenance
        provenance.resource.target << FHIR::Reference.new
        provenance.resource.target.last.reference = "urn:uuid:#{dev.id}"
        puts "  - Cloned Device: #{selection_device.entry.first.resource.id}"
      end

      # select an Immunization
      selection_immunization = results.find {|b| DataScript::Constraints.has(b, FHIR::Immunization)}
      if selection_immunization
        # if there is an Immunization resource, we need to clone it and use carrierAIDC.
        immunization_entry = selection_immunization.entry.find { |e| e.resource.resourceType == 'Immunization' }
        immunization = immunization_entry.resource
        immunization.vaccineCode = create_codeable_concept('http://terminology.hl7.org/CodeSystem/data-absent-reason', 'unknown', 'Unknown')
        immunization.statusReason = create_codeable_concept('http://terminology.hl7.org/CodeSystem/v3-ActReason', 'OSTOCK', 'product out of stock')
        immunization.status = 'not-done'
        puts "  - Altered Immunization: #{selection_immunization.entry.first.resource.id}"
      end

      # select Bundle with Pulse Oximetry
      selection_pulse_ox = results.find {|b| DataScript::Constraints.has_pulse_ox(b)}
      if selection_pulse_ox
        provenance = selection_device.entry.find { |e| e.resource.resourceType == 'Provenance' }
        pulse_ox_entry = selection_pulse_ox.entry.find {|e| e.resource&.meta&.profile&.include? 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry' }
        pulse_ox_clone = nil
        2.times do
          pulse_ox_clone = FHIR.from_contents(pulse_ox_entry.resource.to_json)
          pulse_ox_clone.id = SecureRandom.uuid
          # Add the must support components
          pulse_ox_clone.component = []
          # First component is flow rate
          pulse_ox_clone.component << FHIR::Observation::Component.new
          pulse_ox_clone.component.last.code = create_codeable_concept('http://loinc.org','3151-8', 'Inhaled oxygen flow rate')
          pulse_ox_clone.component.last.valueQuantity = FHIR::Quantity.new
          pulse_ox_clone.component.last.valueQuantity.value = 6
          pulse_ox_clone.component.last.valueQuantity.unit = 'l/min'
          pulse_ox_clone.component.last.valueQuantity.system = 'http://unitsofmeasure.org'
          pulse_ox_clone.component.last.valueQuantity.code = 'l/min'
          # Second component is concentration
          pulse_ox_clone.component << FHIR::Observation::Component.new
          pulse_ox_clone.component.last.code = create_codeable_concept('http://loinc.org','3150-0', 'Inhaled oxygen concentration')
          pulse_ox_clone.component.last.valueQuantity = FHIR::Quantity.new
          pulse_ox_clone.component.last.valueQuantity.value = 40
          pulse_ox_clone.component.last.valueQuantity.unit = '%'
          pulse_ox_clone.component.last.valueQuantity.system = 'http://unitsofmeasure.org'
          pulse_ox_clone.component.last.valueQuantity.code = '%'
          # add the Pulse Oximetry as a new Bundle entry
          selection_pulse_ox.entry << create_bundle_entry(pulse_ox_clone)
          # add the Pulse Oximetry into the provenance
          provenance.resource.target << FHIR::Reference.new
          provenance.resource.target.last.reference = "urn:uuid:#{pulse_ox_clone.id}"
        end
        # for the second clone, data absent reason the components
        pulse_ox_clone.component.each do |component|
          component.valueQuantity = nil
          component.dataAbsentReason = create_codeable_concept('http://terminology.hl7.org/CodeSystem/data-absent-reason', 'unknown', 'Unknown')
        end
        puts "  - Cloned Pulse Oximetry and Added Components: #{selection_pulse_ox.entry.first.resource.id}"
      end

      goal_bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::Goal) }
      unless goal_bundle
        goal_bundle = results.find { |b| DataScript::Constraints.has(b, FHIR::Patient) }
        goal = FHIR::Goal.new
        goal.meta = FHIR::Meta.new
        goal.meta.profile = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-goal'
        goal.id = SecureRandom.uuid
        goal.lifecycleStatus = 'active'
        goal.description = create_codeable_concept('http://snomed.info/sct', '281004', 'Alcoholic dementia')
        goal.subject = { reference: "urn:uuid:#{DataScript::Constraints.patient(goal_bundle).id}" }
        goal_target = FHIR::Goal::Target.new
        goal_target.dueDate = Time.now.strftime("%Y-%m-%d")
        goal.target << goal_target
        goal_bundle.entry << create_bundle_entry(goal)
        goal_provenance = goal_bundle.entry.find { |e| e.resource.resourceType == 'Provenance' }
        goal_provenance.resource.target << FHIR::Reference.new
        goal_provenance.resource.target.last.reference = "urn:uuid:#{goal.id}"
      end

      # Observation Data Absent Reasons
      # observation_profiles_valueQuantity_required = [
      #   'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-bmi-for-age',
      #   'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-weight-for-height',
      #   'http://hl7.org/fhir/StructureDefinition/bmi',
      # ]
      observation_profiles_valueCodeableConcept_required = [
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-smokingstatus'
      ]
      observation_profiles_components_required = [
        'http://hl7.org/fhir/StructureDefinition/bp'
      ]
      observation_profiles = [
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab',
        # 'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-bmi-for-age',
        # 'http://hl7.org/fhir/us/core/StructureDefinition/pediatric-weight-for-height',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-smokingstatus',
        'http://hl7.org/fhir/us/core/StructureDefinition/us-core-pulse-oximetry',
        'http://hl7.org/fhir/StructureDefinition/resprate',
        'http://hl7.org/fhir/StructureDefinition/heartrate',
        'http://hl7.org/fhir/StructureDefinition/bodytemp',
        'http://hl7.org/fhir/StructureDefinition/bodyheight',
        'http://hl7.org/fhir/StructureDefinition/headcircum',
        'http://hl7.org/fhir/StructureDefinition/bodyweight',
        # 'http://hl7.org/fhir/StructureDefinition/bmi',
        'http://hl7.org/fhir/StructureDefinition/bp'
      ]

      resources_with_multiple_mustsupport_references = {
        FHIR::CareTeam => [
          {
            fhirpath: 'participant.member',
            required_ref_types: [
              FHIR::Patient,
              FHIR::Practitioner,
              FHIR::Organization
            ],
            base_object: FHIR::CareTeam::Participant.new.from_hash({ role: [{ coding: [{ code: '223366009', system: 'http://snomed.info/sct', display: 'Healthcare provider' }] }] })
          },
        ],
        # NOTE: DiagnosticReport should be here, but because of the difficulties around the two profiles, we handle it elsewhere
        FHIR::DocumentReference => [
          {
            fhirpath: 'author',
            required_ref_types: [
              FHIR::Patient,
              FHIR::Practitioner,
              FHIR::Organization
            ],
            base_object: nil
          }
        ],
        FHIR::MedicationRequest => [
          {
            fhirpath: 'reportedReference',
            required_ref_types: [
              FHIR::Patient,
              FHIR::Practitioner,
              FHIR::Organization
            ],
            base_object: :self
          },
          {
            fhirpath: 'requester',
            required_ref_types: [
              FHIR::Patient,
              FHIR::Practitioner,
              FHIR::Organization,
              FHIR::Device
            ],
            base_object: :self
          }
        ],
        FHIR::Provenance => [
          {
            fhirpath: 'agent.who',
            required_ref_types: [
              FHIR::Patient,
              FHIR::Practitioner,
              FHIR::Organization
            ],
            base_object: FHIR::Provenance::Agent.new.from_hash({
              type: {
                coding: [
                  {
                    code: 'author',
                    display: 'Author',
                    system: 'http://terminology.hl7.org/CodeSystem/provenance-participant-type'
                  }
                ]
              }
            })
          }
        ]
      }

      puts "  - Processing Observation Data Absent Reasons"
      results.each do |bundle|
        break if observation_profiles.empty?
        observation_profiles.delete_if do |profile_url|
          entry = bundle.entry.find {|e| e.resource.resourceType == 'Observation' && e.resource.meta&.profile&.include?(profile_url) }
          if entry
            instance = entry.resource
            instance.dataAbsentReason = create_codeable_concept('http://terminology.hl7.org/CodeSystem/data-absent-reason', 'unknown', 'Unknown')
            # if observation_profiles_valueQuantity_required.include?(profile_url)
            #   instance.dataAbsentReason = nil
            #   instance.valueQuantity.value = 'DATAABSENTREASONEXTENSIONGOESHERE' # Flag for primitive extension
            # elsif
            if observation_profiles_valueCodeableConcept_required.include?(profile_url)
              instance.valueCodeableConcept = instance.dataAbsentReason
              instance.dataAbsentReason = nil
            elsif observation_profiles_components_required.include?(profile_url)
              instance.component.each do |component|
                component.valueQuantity = nil
                component.dataAbsentReason = instance.dataAbsentReason
              end
            else
              instance.valueQuantity = nil
            end
            puts "    - #{profile_url}: #{entry.fullUrl}"
            true # delete this profile url from the list
          else
            false # keep searching for this profile url in the next bundle
          end
        end
      end
      unless observation_profiles.empty?
        puts "  * Missed Observation Data Absent Reasons"
        observation_profiles.each do |profile_url|
          puts "    ** #{profile_url}"
        end
      end

      # remove all resources from bundles that are not US Core profiles
      results.each do |bundle|
        bundle.entry.delete_if {|e| ['Claim','ExplanationOfBenefit','ImagingStudy'].include?(e.resource.resourceType)}
      end
      puts "  - Removed resources out of scope for US Core."
      # There are probably some observations remaining after this that are not US Core profiles,
      # but they likely are referenced from DiagnosticReports which are US Core profiled.

      # delete provenance references to removed resources
      results.each do |bundle|
        provenance = bundle.entry.find {|e| e.resource.resourceType == 'Provenance' }.resource
        uuids = bundle.entry.map {|e| e.fullUrl}
        provenance.target.keep_if {|reference| uuids.include?(reference.reference) }
      end
      puts "  - Rewrote Provenance targets."

      bundle_with_all = results.find do |b|
        DataScript::Constraints.has(b, FHIR::Patient) &&
          DataScript::Constraints.has(b, FHIR::Practitioner) &&
          DataScript::Constraints.has(b, FHIR::Organization) &&
          DataScript::Constraints.has(b, FHIR::Device) &&
          DataScript::Constraints.has(b, FHIR::CareTeam) &&
          DataScript::Constraints.has(b, FHIR::DiagnosticReport) &&
          DataScript::Constraints.has(b, FHIR::DocumentReference) &&
          DataScript::Constraints.has(b, FHIR::Provenance)
      end
      references = {
        FHIR::Patient => { reference: "urn:uuid:#{bundle_with_all.entry.find { |e| e.resource.is_a? FHIR::Patient }&.resource&.id}" },
        FHIR::Practitioner => { reference: "urn:uuid:#{bundle_with_all.entry.find { |e| e.resource.is_a? FHIR::Practitioner }&.resource&.id}" },
        FHIR::Organization => { reference: "urn:uuid:#{bundle_with_all.entry.find { |e| e.resource.is_a? FHIR::Organization }&.resource&.id}" },
        FHIR::Device => { reference: "urn:uuid:#{bundle_with_all.entry.find { |e| e.resource.is_a? FHIR::Device }&.resource&.id}" }
      }

      resources_with_multiple_mustsupport_references.each do |resource_class, reference_attrs|
        resources = bundle_with_all.entry.find_all { |e| e.resource.is_a? resource_class }.map { |e| e.resource }
        resources.each do |resource|
          reference_attrs.each do |attrs|
            begin
              extant_ref_types = FHIRPath.evaluate(attrs[:fhirpath], resource&.to_hash)
                                        .collect { |ref| get_reference_type(bundle_with_all, ref['reference']) }
                                        .uniq
            rescue
              extant_ref_types = []
            end
            # Subtracting one array from the other will provide a list of elements
            # in needed_ref_types that aren't in extant_ref_types
            missing_ref_types = attrs[:required_ref_types] - extant_ref_types
            missing_ref_types.each do |missing_type|
              missing_reference = references[missing_type]
              if attrs[:base_object] == :self
                ref_obj = FHIR::Json.from_json(resource.to_json)
                ref_obj.id = SecureRandom.uuid
                ref_obj.send("#{attrs[:fhirpath]}=", missing_reference)
                bundle_with_all.entry << create_bundle_entry(ref_obj)
              elsif !attrs[:base_object].nil?
                fhirpath_split = attrs[:fhirpath].split('.')
                ref_obj = attrs[:base_object].class.new.from_hash(attrs[:base_object].to_hash)
                ref_obj.send("#{fhirpath_split.last}=", missing_reference)
                resource.send(fhirpath_split.first).push(ref_obj)
              else
                resource.send(attrs[:fhirpath]).push(missing_reference)
              end
            end
          end
        end
      end

      # DiagnosticReports need to have two performer types, so we add them here
      dr_bundle = results.find do |b|
        b.entry.any? do |e|
          e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta.profile.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note')
        end &&
          b.entry.any? do |e|
            e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta.profile.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab')
          end
      end
      dr_notes = dr_bundle.entry.find_all do |e|
        e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta.profile.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-note')
      end.map {|e| e.resource }
      dr_labs = dr_bundle.entry.find_all do |e|
        e.resource.is_a?(FHIR::DiagnosticReport) && e.resource.meta.profile.include?('http://hl7.org/fhir/us/core/StructureDefinition/us-core-diagnosticreport-lab')
      end.map {|e| e.resource }
      dr_practitioner = dr_bundle.entry.find { |e| e.resource.is_a? FHIR::Practitioner }.resource.id
      dr_organization = dr_bundle.entry.find { |e| e.resource.is_a? FHIR::Organization }.resource.id
      puts "DR Practitioner id: #{dr_practitioner}"
      puts "DR Org ID: #{dr_organization}"
      dr_notes.concat(dr_labs).each do |dr|
        dr.performer << { reference: "urn:uuid:#{dr_practitioner}" }
        dr.performer << { reference: "urn:uuid:#{dr_organization}" }
      end

      # Add Group
      results << create_group(results)

      # The JSON from this exported patient will need to be manually altered to
      # create primitive extensions, so we specifically return just this patient bundle.
      selection_name
    end

    def self.pick_by_gender(results)
      # pick someone of the more represented gender
      # in other words, if there are more males, pick a male.
      # otherwise if there are more females, pick a female.
      females = results.count {|b| b.entry.first.resource.gender == 'female'}
      males = results.length - females
      if males > females
        selection = results.find {|b| b.entry.first.resource.gender == 'male'}
      else
        selection = results.find {|b| b.entry.first.resource.gender == 'female'}
      end
      selection
    end

    def self.remove_name(bundle)
      # Replace name with empty name.
      # Technically this doesn't validate because of us-core-8:
      # Patient.name.given or Patient.name.family or both SHALL be present [family.exists() or given.exists()]
      #
      # The JSON from this exported patient will need to be manually altered to
      # create primitive extensions.
      human_name = FHIR::HumanName.new
      # If the us-core-8 invariant changes to allow data absent reason on name, then we can enable the next line
      # human_name.extension = [ data_absent_reason ]
      bundle.entry.first.resource.name = [ human_name ]
    end

    def self.alter_condition(bundle)
      # randomly pick one of their Conditions
      random_condition = bundle.entry.map {|e| e.resource }.select {|r| r.resourceType == 'Condition'}.shuffle.last
      # and replace the category with a data-absent-reason
      unknown = FHIR::CodeableConcept.new
      unknown.extension = [ data_absent_reason ]
      random_condition.category = [ unknown ]
    end

    def self.data_absent_reason
      extension = FHIR::Extension.new
      extension.url = 'http://hl7.org/fhir/StructureDefinition/data-absent-reason'
      extension.valueCode = 'unknown'
      extension
    end

    def self.alter_smoking_status(bundle)
      last_smoking_observation = bundle.entry.select {|e| e.resource.resourceType == 'Observation' && e.resource.code.text == 'Tobacco smoking status NHIS' }.last.resource
      coding = FHIR::Coding.new
      coding.system = 'http://snomed.info/sct'
      coding.code = '449868002'
      coding.display = 'Current every day smoker'
      smoker = FHIR::CodeableConcept.new
      smoker.coding = [ coding ]
      smoker.text = 'Current every day smoker'
      last_smoking_observation.valueCodeableConcept = smoker
    end

    def self.create_group(results)
      group = FHIR::Group.new
      group.id = SecureRandom.uuid
      group.identifier = [ FHIR::Identifier.new ]
      group.identifier.first.system = 'urn:ietf:rfc:3986'
      group.identifier.first.value = "urn:uuid:#{group.id}"
      group.active = true
      group.type = 'person'
      group.actual = true
      group.name = 'Synthea US Core Patients'
      group.quantity = results.length
      group.member = []
      results.each do |bundle|
        group_member = FHIR::Group::Member.new
        group_member.entity = FHIR::Reference.new
        group_member.entity.reference = bundle.entry.first.fullUrl
        group.member << group_member
      end
      group
    end

    def self.create_codeable_concept(system, code, display)
      coding = FHIR::Coding.new
      coding.system = system
      coding.display = display
      coding.code = code
      codeableconcept = FHIR::CodeableConcept.new
      codeableconcept.text = display
      codeableconcept.coding = [ coding ]
      codeableconcept
    end

    def self.create_bundle_entry(resource)
        entry = FHIR::Bundle::Entry.new
        entry.fullUrl = "urn:uuid:#{resource.id}"
        entry.resource = resource
        entry.request = FHIR::Bundle::Entry::Request.new
        entry.request.local_method = 'POST'
        entry.request.url = resource.resourceType
        entry
    end

    def self.get_reference_type(b, reference_string)
      id = reference_string.split(':').last
      b.entry.find { |e| e.resource.id == id }&.resource&.class
    end
  end
end
