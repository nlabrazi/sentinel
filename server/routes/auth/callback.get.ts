import { handleOidcCallback } from '#server/utils/oidc-callback'

export default defineEventHandler((event) => handleOidcCallback(event))
