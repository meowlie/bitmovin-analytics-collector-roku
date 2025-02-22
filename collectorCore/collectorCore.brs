sub init()
  m.version = "2.2.0"
  m.tag = "Bitmovin Analytics Collector [collectorCore] "
  m.appInfo = CreateObject("roAppInfo")
  m.domain = m.appInfo.GetID() + ".roku"
  m.deviceInfo = CreateObject("roDeviceInfo")
  m.sectionRegistryName = "BitmovinAnalytics"
  m.analyticsDataTask = m.top.findNode("analyticsDataTask")
  m.analyticsConfig = CreateObject("roAssociativeArray")
  m.sample = invalid
end sub

sub initializeAnalytics(config = invalid)
  ' Set licenseKey if present in analytics configuration
  if config <> invalid and config.DoesExist("key")
    setLicenseKey(config.key)
  end if

  checkAnalyticsLicenseKey()
  setupSample()

  updateAnalyticsConfig(config)
end sub

' #region Licensing

sub checkAnalyticsLicenseKey()
  if isInvalid(m.analyticsDataTask) then return

  m.analyticsDataTask.licensingData = getLicensingData()
  m.analyticsDataTask.checkLicenseKey = true
end sub

function getLicensingData()
  licenseKey = getLicenseKey()

  if isInvalid(licenseKey) or Len(licenseKey) = 0
    print m.tag; "Warning: license key is not present in the analyticsConfig or manifest, or is set as an empty string."
  end if

  return {
    key : licenseKey,
    domain : m.domain,
    analyticsVersion : getVersion()
  }
end function

' Returns Bitmovin analytics license key that is set in the analytics configuration or the manifest (as fallback), or invalid.
function getLicenseKey()
  if isInvalid(m.analyticsConfig) or isInvalid(m.appInfo) return invalid

  licenseKey = pluck(m.analyticsConfig, ["key"])
  if isInvalid(licenseKey)
    licenseKey = m.appInfo.getValue("bitmovin_analytics_license_key")
  end if

  return licenseKey
end function

sub setLicenseKey(licenseKey)
  m.analyticsConfig.key = licenseKey
end sub

' #endregion

' Sets up sample that is sent to Bitmovin Analytics.
sub setupSample()
  if isInvalid(m.sample)
    m.sample = getAnalyticsSample()
  end if
  m.sample.analyticsVersion = getVersion()
  m.sample.key = getLicenseKey()
  m.sample.domain = m.domain
  m.sample.userAgent = getUserAgent()
  m.sample.screenHeight = m.deviceInfo.GetDisplaySize().h
  m.sample.screenWidth = m.deviceInfo.GetDisplaySize().w
  m.sample.userId = getPersistedUserId(m.sectionRegistryName)

  m.sample.sequenceNumber = 0
  m.sample.impressionId = createImpressionId()
  m.sample.deviceInformation = getDeviceInformation()
end sub

sub clearSampleValues()
  m.sample.ad = 0
  m.sample.paused = 0
  m.sample.played = 0
  m.sample.seeked = 0
  m.sample.buffered = 0

  m.sample.playerStartupTime = 0
  m.sample.videoStartupTime = 0
  m.sample.startupTime = 0

  m.sample.duration = 0
  m.sample.droppedFrames = 0

  m.sample.errorCode = invalid
  m.sample.errorMessage = invalid
end sub

function getVersion(param = invalid)
  return m.version
end function

function getUserAgent(param = invalid)
  ' TODO: Replace deprecated method with `m.deviceInfo.GetOSVersion()`.
  ' See https://developer.roku.com/en-gb/docs/references/brightscript/interfaces/ifdeviceinfo.md#getosversion-as-object
  version=m.deviceInfo.GetVersion()
  versionMajor=mid(version,3,1)
  versionMinor=mid(version,5,2)
  versionBuild=mid(version,8,5)

  if versionMinor.toint() < 10 then
      versionMinor=mid(versionMinor,2)
  end if
  return "Roku/DVP-"+versionMajor+"."+versionMinor+" ("+version+")"
end function

function getDeviceInformation(param = invalid)
 return {
    manufacturer: m.deviceInfo.GetModelDetails().VendorName,
    model: m.deviceInfo.GetModel(),
    isTV: m.deviceInfo.GetModelType() = "TV"
 }
end function

function createImpressionId(param = invalid)
  return lcase(m.deviceInfo.GetRandomUUID())
end function

function getCurrentImpressionId(param = invalid)
  return m.sample.impressionId
end function

function getPersistedUserId(sectionRegistryName)
  if sectionRegistryName = invalid
    return invalid
  end if

  persistedUserIdRegistryKey = "userId"
  userId = readFromRegistry(sectionRegistryName, persistedUserIdRegistryKey)
  if userId = invalid
    userId = m.deviceInfo.GetRandomUUID()
    userIdData = {key: persistedUserIdRegistryKey, value: userId}
    writeToRegistry(sectionRegistryName, userIdData)
  end if

  return userId
end function

' TODO: Error handling if the keys are invalid
sub sendAnalyticsRequestAndClearValues()
  m.analyticsDataTask.eventData = m.sample
  m.sample.sequenceNumber++

  sendAnalyticsRequest()
  clearSampleValues()
end sub

sub createTempMetadataSampleAndSendAnalyticsRequest(updatedSampleData)
  if updatedSampleData = invalid return

  sendOnceSample = createSendOnceSample(updatedSampleData)
  m.analyticsDataTask.eventData = sendOnceSample

  sendAnalyticsRequest()
end sub

function updateSample(newSampleData)
  if newSampleData = invalid then return false

  m.sample.append(newSampleData)

  return true
end function

sub setVideoTimeStart(time)
  m.sample.videoTimeStart = time
end sub

sub setVideoTimeEnd(time)
  m.sample.videoTimeEnd = time
end sub

function createSendOnceSample(metadata)
  if metadata = invalid then return invalid
  tempSample = {}
  tempSample.append(m.sample)
  tempSample.append(metadata)

  return tempSample
end function

sub sendAnalyticsRequest()
  m.analyticsDataTask.sendData = true
end sub

Function readFromRegistry(registrySectionName, readKey)
     registrySection = CreateObject("roRegistrySection", registrySectionName)
     if registrySection.Exists(readKey)
         return registrySection.Read(readKey)
     end if
     return invalid
End Function

Function writeToRegistry(registrySectionName, dataToWrite)
    registrySection = CreateObject("roRegistrySection", registrySectionName)
    key = dataToWrite.key
    value = dataToWrite.value
    registrySection.Write(key, value)
    registrySection.Flush()
End Function

' Extract valid analytics configuration fields from the config object.
' This metadata object will be merged with the sample! Make sure that fields are valid sample attributes.
' @return A valid analytics configuration which can be appended to analytics samples
function getMetadataFromAnalyticsConfig(config)
  if config = invalid then return {}

  metadata = {
    isLive: false
  }

  if config.DoesExist("cdnProvider")
    metadata.cdnProvider = config.cdnProvider
  end if
  if config.DoesExist("videoId")
    metadata.videoId = config.videoId
  end if
  if config.DoesExist("title")
    metadata.videoTitle = config.title
  end if
  if config.DoesExist("customUserId")
    metadata.customUserId = config.customUserId
  end if

  ' Check `customDataX` fields
  for i = 1 to 25
    customDataField = "customData" + i.ToStr()
    if config.DoesExist(customDataField)
      metadata[customDataField] = config[customDataField]
    end if
  end for

  if config.DoesExist("experimentName")
    metadata.experimentName = config.experimentName
  end if
  if config.DoesExist("isLive")
    metadata.isLive = config.isLive
  end if
  return metadata
end function

sub guardAgainstMissingVideoTitle(config)
  if config <> invalid and config.DoesExist("title") = true then return
  print m.tag; "The new analytics configuration does not contain the field `title`"
end sub

sub guardAgainstMissingIsLive(config)
  if config <> invalid and config.DoesExist("isLive") = true then return
  print m.tag; "The new analytics configuration does not contain the field `isLive`. It will default to `false` which might be unintended? Once stream playback information is available the type will be populated."
end sub

sub updateAnalyticsConfig(unsanitizedConfig)
  ' First check for missing fields and then extract metadata (renaming of fields happens here)
  guardAgainstMissingVideoTitle(unsanitizedConfig)
  guardAgainstMissingIsLive(unsanitizedConfig)

  config = getMetadataFromAnalyticsConfig(unsanitizedConfig)

  mergedConfig = {}
  mergedConfig.Append(m.analyticsConfig)
  mergedConfig.Append(config)
  m.analyticsConfig = mergedConfig

  updateSample(m.analyticsConfig)
end sub
