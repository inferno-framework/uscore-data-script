require 'pry'
require 'fhir_models'
require 'fileutils'
require './lib/time.rb'
require './lib/constraints.rb'
require './lib/modifications.rb'
require './lib/bulk_data_converter.rb'

start = Time.now.to_i

if ARGV && ARGV.length >= 1 && ARGV.include?('mrburns')
  puts 'Generating Mr. Burns...'
  MRBURNS=true
  DataScript::Constraints::CONSTRAINTS_MRBURNS_DOES_NOT_NEED.each do |key|
    DataScript::Constraints::CONSTRAINTS.delete(key)
  end
  DataScript::Constraints::CONSTRAINTS.merge!(DataScript::Constraints::CONSTRAINTS_MRBURNS)
  DataScript::Constraints::REQUIRED_PROFILES.delete('http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication')
else
  MRBURNS=false
end

puts 'Generating Synthetic Patients with Synthea...'
output = 'output'
output_raw = 'output/raw'
output_raw_fhir = 'output/raw/fhir'
FileUtils.rm Dir.glob("./#{output}/*.log")
Dir.mkdir(output) unless File.exists?(output)
Dir.mkdir(output_raw) unless File.exists?(output_raw)
Dir.mkdir(output_raw_fhir) unless File.exists?(output_raw_fhir)
FileUtils.rm Dir.glob("./#{output_raw_fhir}/*.json")

# Manually list out the classpath, because it needs to be loaded in a specific order...
CLASSPATH='lib/synthea/synthea.jar:lib/synthea/SimulationCoreLibrary_v1.5_slim.jar:lib/synthea/hapi-fhir-structures-dstu3-4.1.0.jar:lib/synthea/hapi-fhir-structures-dstu2-4.1.0.jar:lib/synthea/hapi-fhir-structures-r4-4.1.0.jar:lib/synthea/org.hl7.fhir.dstu3-4.1.0.jar:lib/synthea/org.hl7.fhir.r4-4.1.0.jar:lib/synthea/org.hl7.fhir.utilities-4.1.0.jar:lib/synthea/hapi-fhir-base-4.1.0.jar:lib/synthea/gson-2.8.5.jar:lib/synthea/json-path-2.4.0.jar:lib/synthea/freemarker-2.3.26-incubating.jar:lib/synthea/h2-1.4.196.jar:lib/synthea/guava-28.0-jre.jar:lib/synthea/graphviz-java-0.2.2.jar:lib/synthea/commons-csv-1.5.jar:lib/synthea/jackson-dataformat-csv-2.8.8.jar:lib/synthea/snakeyaml-1.25.jar:lib/synthea/commons-math3-3.6.1.jar:lib/synthea/commons-text-1.7.jar:lib/synthea/cql-engine-1.3.10-SNAPSHOT.jar:lib/synthea/cql-to-elm-1.3.17.jar:lib/synthea/cql-1.3.17.jar:lib/synthea/elm-1.3.17.jar:lib/synthea/model-1.3.17.jar:lib/synthea/jaxb-runtime-2.3.0.jar:lib/synthea/jaxb-core-2.3.0.jar:lib/synthea/jaxb-api-2.3.0.jar:lib/synthea/activation-1.1.1.jar:lib/synthea/quick-1.3.17.jar:lib/synthea/qdm-1.3.17.jar:lib/synthea/jaxb2-basics-0.9.4.jar:lib/synthea/jaxb2-basics-tools-0.9.4.jar:lib/synthea/jcl-over-slf4j-1.7.28.jar:lib/synthea/jul-to-slf4j-1.7.25.jar:lib/synthea/slf4j-log4j12-1.7.25.jar:lib/synthea/jsbml-1.4.jar:lib/synthea/jsbml-arrays-1.4.jar:lib/synthea/jsbml-comp-1.4.jar:lib/synthea/jsbml-distrib-1.3.1.jar:lib/synthea/jsbml-dyn-1.4.jar:lib/synthea/jsbml-fbc-1.4.jar:lib/synthea/jsbml-groups-1.4.jar:lib/synthea/jsbml-render-1.4.jar:lib/synthea/jsbml-layout-1.4.jar:lib/synthea/jsbml-multi-1.4.jar:lib/synthea/jsbml-qual-1.4.jar:lib/synthea/jsbml-req-1.4.jar:lib/synthea/jsbml-spatial-1.4.jar:lib/synthea/jsbml-tidy-1.4.jar:lib/synthea/jsbml-core-1.4.jar:lib/synthea/biojava-ontology-4.0.0.jar:lib/synthea/log4j-slf4j-impl-2.1.jar:lib/synthea/slf4j-api-1.7.28.jar:lib/synthea/commons-math-2.2.jar:lib/synthea/jfreechart-1.5.0.jar:lib/synthea/json-smart-2.3.jar:lib/synthea/commons-lang3-3.9.jar:lib/synthea/commons-codec-1.12.jar:lib/synthea/batik-codec-1.9.jar:lib/synthea/batik-rasterizer-1.9.jar:lib/synthea/batik-svgrasterizer-1.9.jar:lib/synthea/batik-transcoder-1.9.jar:lib/synthea/batik-bridge-1.9.jar:lib/synthea/batik-script-1.9.jar:lib/synthea/batik-anim-1.9.jar:lib/synthea/batik-svg-dom-1.9.jar:lib/synthea/batik-dom-1.9.jar:lib/synthea/batik-css-1.9.jar:lib/synthea/xmlgraphics-commons-2.2.jar:lib/synthea/commons-io-2.6.jar:lib/synthea/ucum-1.0.2.jar:lib/synthea/jsr305-3.0.2.jar:lib/synthea/j2v8_macosx_x86_64-4.6.0.jar:lib/synthea/j2v8_linux_x86_64-4.6.0.jar:lib/synthea/j2v8_win32_x86_64-4.6.0.jar:lib/synthea/j2v8_win32_x86-4.6.0.jar:lib/synthea/commons-exec-1.3.jar:lib/synthea/jackson-databind-2.10.1.jar:lib/synthea/jackson-core-2.10.1.jar:lib/synthea/jackson-annotations-2.10.1.jar:lib/synthea/jaxb2-fluent-api-3.0.jar:lib/synthea/hamcrest-all-1.3.jar:lib/synthea/hamcrest-json-0.2.jar:lib/synthea/jaxb-impl-2.3.0.1.jar:lib/synthea/jaxb-core-2.3.0.1.jar:lib/synthea/javax.activation-1.2.0.jar:lib/synthea/eclipselink-2.6.0.jar:lib/synthea/validation-api-1.1.0.Final.jar:lib/synthea/antlr4-4.5.jar:lib/synthea/jopt-simple-4.7.jar:lib/synthea/stax-ex-1.7.8.jar:lib/synthea/FastInfoset-1.2.13.jar:lib/synthea/accessors-smart-1.2.jar:lib/synthea/failureaccess-1.0.1.jar:lib/synthea/listenablefuture-9999.0-empty-to-avoid-conflict-with-guava.jar:lib/synthea/checker-qual-2.8.1.jar:lib/synthea/error_prone_annotations-2.3.2.jar:lib/synthea/j2objc-annotations-1.3.jar:lib/synthea/animal-sniffer-annotations-1.17.jar:lib/synthea/xpp3-1.1.4c.jar:lib/synthea/xpp3_xpath-1.1.4c.jar:lib/synthea/json-simple-1.1.1.jar:lib/synthea/junit-4.12.jar:lib/synthea/batik-parser-1.9.jar:lib/synthea/batik-gvt-1.9.jar:lib/synthea/batik-svggen-1.9.jar:lib/synthea/batik-awt-util-1.9.jar:lib/synthea/batik-xml-1.9.jar:lib/synthea/batik-util-1.9.jar:lib/synthea/xalan-2.7.2.jar:lib/synthea/serializer-2.7.2.jar:lib/synthea/xml-apis-1.3.04.jar:lib/synthea/jaxb2-basics-runtime-0.9.4.jar:lib/synthea/javaparser-1.0.11.jar:lib/synthea/jsonassert-1.1.1.jar:lib/synthea/hamcrest-core-1.3.jar:lib/synthea/log4j-1.2.17.jar:lib/synthea/javax.persistence-2.1.0.jar:lib/synthea/commonj.sdo-2.1.1.jar:lib/synthea/javax.json-1.0.4.jar:lib/synthea/antlr4-runtime-4.5.jar:lib/synthea/ST4-4.0.8.jar:lib/synthea/antlr-runtime-3.5.2.jar:lib/synthea/txw2-2.3.0.jar:lib/synthea/istack-commons-runtime-3.0.5.jar:lib/synthea/log4j-1.2-api-2.3.jar:lib/synthea/log4j-core-2.3.jar:lib/synthea/woodstox-core-5.0.1.jar:lib/synthea/jigsaw-2.2.6.jar:lib/synthea/xstream-1.3.1.jar:lib/synthea/staxmate-2.3.0.jar:lib/synthea/jtidy-r938.jar:lib/synthea/asm-5.0.4.jar:lib/synthea/batik-ext-1.9.jar:lib/synthea/xml-apis-ext-1.3.04.jar:lib/synthea/batik-constants-1.9.jar:lib/synthea/batik-i18n-1.9.jar:lib/synthea/commons-beanutils-1.9.2.jar:lib/synthea/json-20090211.jar:lib/synthea/commons-collections-3.2.1.jar:lib/synthea/org.abego.treelayout.core-1.0.1.jar:lib/synthea/log4j-api-2.3.jar:lib/synthea/stax2-api-3.1.4.jar:lib/synthea/xpp3_min-1.1.4c.jar:lib/synthea/commons-logging-1.0.4.jar'

CONFIG='--exporter.fhir.use_us_core_ig=true --exporter.baseDirectory=./output/raw --exporter.hospital.fhir.export=false --exporter.practitioner.fhir.export=false --exporter.groups.fhir.export=true'

if MRBURNS
  system( "java -cp #{CLASSPATH} App -s 0 -a 80-81 -g M -p 20 #{CONFIG} --exporter.years_of_history=0 > output/synthea.log" )
else
  system( "java -cp #{CLASSPATH} App -s 3 -p 205 #{CONFIG} > output/synthea.log" )
end
tok = Time.now.to_i
puts "  Generated data in #{DataScript::TimeUtilities.pretty(tok - start)}."

puts 'Loading FHIR Bundles...'
records = []
all_group = nil
input_folder = File.join(File.dirname(__FILE__), './output/raw/fhir')
Dir.foreach(input_folder) do |file|
  next unless file.end_with?('.json')
  next if file.start_with?('hospitalInformation', 'practitionerInformation')
  json = File.open("#{input_folder}/#{file}", 'r:UTF-8', &:read)
  bundle = FHIR.from_contents(json)
  if bundle.resourceType == 'Group'
    all_group = bundle
  elsif bundle.resourceType == 'Bundle'
    records << bundle
  end
end
tik = Time.now.to_i
puts "  Loaded #{records.length} FHIR Bundles in #{DataScript::TimeUtilities.pretty(tik - tok)}."

# Constraints to test
constraints = DataScript::Constraints.new
# Selections (plural) is the patient bundles selected that satisfy the constraints
selections = []
# Selection (singular) is the latest selected patient bundle
selection = nil
# Satsified is the list of the named constraints (as strings) that the current selections satisfy.
satisfied = []
# Unsatisfied is the list of the named constraints (as strings) that have yet to be satisified.
unsatisfied = DataScript::Constraints::CONSTRAINTS.keys - satisfied

puts 'Selecting patients by constraints...'
# while there are more constraints to satisfy, there are still patient records remaining to choose from,
# or the remaining patient records are still useful (e.g. they are satisfying additional constraints)
until unsatisfied.empty? || records.empty? || selection&.total == 0
  # Score each patient against the unsatisfied constraints
  puts '  Scoring Records...'
  records.each do |bundle|
    constraints.satisfied?([bundle], unsatisfied)
    bundle.total = unsatisfied.length - constraints.violations.length
  end

  # Sort the patients, first worse, last best
  # and select the patient that satisfies the most remaining constraints
  records.sort! {|a, b| a.total <=> b.total}
  # puts "  #{records.map {|b| b.total}}" # debug scores
  selection = records.pop

  # Recalculate constraint satisfaction variables
  constraints.satisfied?([selection])
  selection_unsatisfied = constraints.violations
  selection_satisfied = DataScript::Constraints::CONSTRAINTS.keys - selection_unsatisfied

  satisfied = satisfied.append(selection_satisfied).flatten.uniq
  unsatisfied = DataScript::Constraints::CONSTRAINTS.keys - satisfied

  # Add the currently selected patient to our list, as long as it is a useful addition
  if selection.total > 0
    puts "    Selected: #{selection_satisfied}"
    selections << selection
  else
    puts "    Done."
  end
end
selections.each {|bundle| bundle.total = nil}

# How many profiles are supported?
selection = nil
profiles_present = constraints.profiles_present(selections)
profiles_present.append('http://hl7.org/fhir/us/core/StructureDefinition/us-core-medication') if MRBURNS
profiles_missing = DataScript::Constraints::REQUIRED_PROFILES - profiles_present
puts 'Selecting patients by profile...' unless profiles_missing.empty?

until profiles_missing.empty? || records.empty? || selection&.total == 0
  # Score each patient against the unsatisfied constraints
  puts '  Scoring Records...'
  records.each do |bundle|
    bundle_present = constraints.profiles_present([bundle])
    bundle.total = (bundle_present - profiles_present).length
  end

  # Sort the patients, first worse, last best
  # and select the patient that satisfies the most remaining constraints
  records.sort! {|a, b| a.total <=> b.total}
  # puts "  #{records.map {|b| b.total}}" # debug scores
  selection = records.pop

  bundle_present = constraints.profiles_present([selection])
  bundle_extras = bundle_present - profiles_present
  profiles_present = profiles_present.append(bundle_present).flatten.uniq
  profiles_missing = DataScript::Constraints::REQUIRED_PROFILES - profiles_present
  if selection.total > 0
    puts "    Selected: #{bundle_extras}"
    selections << selection
  else
    puts "    Done."
  end
end
selections.each {|bundle| bundle.total = nil}

tok = Time.now.to_i
puts "  Selected #{selections.length} patients (#{DataScript::TimeUtilities.pretty(tok - tik)})."

# post-process selections
puts 'Modifying selected patients...'
patient_bundle_absent_name = DataScript::Modifications.modify!(selections)
tik = Time.now.to_i
puts "  Modified patients (#{DataScript::TimeUtilities.pretty(tik - tok)})."
group = selections.pop

puts 'Final constraint testing...'
if constraints.satisfied?(selections)
  puts '  All constraints satisfied.'
else
  puts "  #{constraints.violations.length} remaining constraints violated: #{constraints.violations}"
end
profiles_present = constraints.profiles_present(selections)
profiles_missing = DataScript::Constraints::REQUIRED_PROFILES - profiles_present
if profiles_missing.empty?
  puts '  All profiles present.'
else
  puts "  Missing #{profiles_missing.length} profiles: #{profiles_missing}"
end

# Add the Group back
selections << group
# Remove the patient with primitive extensions
# because we need to write out their JSON separately.
if patient_bundle_absent_name
  selections.delete(patient_bundle_absent_name)
  records.delete(patient_bundle_absent_name)
end

# Save selections
tik = Time.now.to_i
output_data = 'output/data'
output_validation = 'output/validation'
puts "Overwritting selections into ./#{output_data}"
Dir.mkdir(output_data) unless File.exists?(output_data)
Dir.mkdir(output_validation) unless File.exists?(output_validation)
FileUtils.rm Dir.glob("./#{output_data}/*.json")
FileUtils.rm Dir.glob("./#{output_validation}/*.txt")
selections.each do |bundle|
  if bundle.resourceType == 'Bundle'
    id = bundle.entry.first.resource.id
  else
    id = bundle.id
  end
  filename = "#{output_data}/#{id}.json"
  file = File.open(filename,'w:UTF-8')
  file.write( bundle.to_json )
  file.close
  # run FHIR validator on output
  validation_file = "#{output_validation}/#{id}.txt"
  system( "java -jar lib/org.hl7.fhir.validator.jar #{filename} -version 4.0.1 -ig hl7.fhir.us.core > #{validation_file}" )
end

patient_without_name_json = nil
if patient_bundle_absent_name
  # we need to manually manipulate the JSON for this one bundle,
  # because the fhir_models gem does not support primitive extensions.
  json = JSON.parse( patient_bundle_absent_name.to_json )
  json['entry'][0]['resource']['name'] = [{
    '_family' => {
      'extension' => [ DataScript::Modifications.data_absent_reason.to_hash ]
    },
    '_given' => [{
      'extension' => [ DataScript::Modifications.data_absent_reason.to_hash ]
    }]
  }]
  patient_without_name_json = JSON.unparse(json['entry'][0]['resource'])
  json = JSON.pretty_unparse(json)
  filename = "#{output_data}/#{patient_bundle_absent_name.entry.first.resource.id}.json"
  file = File.open(filename,'w:UTF-8')
  file.write(json)
  file.close
  # run FHIR validator on output
  puts 'Running FHIR validator on output.'
  validation_file = "#{output_validation}/#{patient_bundle_absent_name.entry.first.resource.id}.txt"
  system( "java -jar lib/org.hl7.fhir.validator.jar #{filename} -version 4.0.1 -ig hl7.fhir.us.core > #{validation_file}" )
end

tok = Time.now.to_i
puts "  Saved and validated #{selections.length + (patient_bundle_absent_name ? 1 : 0)} files (#{DataScript::TimeUtilities.pretty(tok - tik)})."

# Save the selection records in the Bulk Data Format
tik = Time.now.to_i

puts 'Saving *selected* records in Bulk Data ndjson format...'
converter = DataScript::BulkDataConverter.new('selected')
selections.each do |bundle|
  converter.convert_to_bulk_data(bundle)
end
converter.convert_to_bulk_data(patient_bundle_absent_name, patient_without_name_json) if patient_bundle_absent_name
converter.close

tok = Time.now.to_i
puts "  Saved #{selections.length + (patient_bundle_absent_name ? 1 : 0)} records as ndjson (#{DataScript::TimeUtilities.pretty(tok - tik)})."

# Save *ALL* the records in the Bulk Data Format
unless MRBURNS
  tik = Time.now.to_i

  puts 'Saving *all* records in Bulk Data ndjson format...'
  converter = DataScript::BulkDataConverter.new('all')
  records.each do |bundle|
    converter.convert_to_bulk_data(bundle)
  end
  converter.convert_to_bulk_data(patient_bundle_absent_name, patient_without_name_json) if patient_bundle_absent_name
  converter.convert_to_bulk_data(group)
  converter.convert_to_bulk_data(all_group)
  converter.close

  tok = Time.now.to_i
  puts "  Saved #{records.length + (patient_bundle_absent_name ? 1 : 0)} records as ndjson (#{DataScript::TimeUtilities.pretty(tok - tik)})."
end

puts 'Cleaning...'
['Claim','ExplanationOfBenefit','ImagingStudy'].each do |resourceType|
  FileUtils.rm Dir.glob("./#{output}/**/#{resourceType}.ndjson")
end

# Print the amount of time it took...
stop = Time.now.to_i
puts "Complete (#{DataScript::TimeUtilities.pretty(stop - start)})"
