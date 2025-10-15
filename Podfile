# Uncomment the next line to define a global platform for your project
platform :ios, '14.0'

target 'RecordPath' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Using Apple's native CoreLocation instead of AMap SDK
  # All location services will be handled by iOS native frameworks
  
  # Firebase SDK
  pod 'Firebase/Analytics'
  pod 'Firebase/Auth'
  pod 'Firebase/Firestore'
  pod 'Firebase/Storage'

  target 'RecordPathTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'RecordPathUITests' do
    # Pods for testing
  end

end