require 'xcodeproj'

project_path = 'DogLens.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  if target.name == 'DogLens'
    target.build_configurations.each do |config|
      config.build_settings['INFOPLIST_KEY_NSCameraUsageDescription'] = '"We need access to your camera to scan dogs."'
      config.build_settings['INFOPLIST_KEY_NSPhotoLibraryUsageDescription'] = '"We need access to your photos to scan dog images."'
      config.build_settings['INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription'] = '"We need access to save annotated images to your library."'
    end
  end
end

project.save
