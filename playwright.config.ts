import { defineSharedPlaywrightConfig } from '@nlabrazi/config-playwright'

export default defineSharedPlaywrightConfig({
  useBuiltServerInCI: true,
})
