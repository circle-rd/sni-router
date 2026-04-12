export default defineNuxtConfig({
  extends: ["docus"],
  app: {
    baseURL: process.env.NUXT_APP_BASE_URL ?? "/sni-router/",
  },
  site: {
    url: process.env.NUXT_SITE_URL ?? "https://docs.circle-cyber.com/sni-router",
  },
  llms: {
    title: "SNI Router",
    description:
      "TLS/SNI passthrough router built on HAProxy — route HTTPS traffic by hostname without decrypting.",
    full: {
      title: "SNI Router — Complete Documentation",
      description:
        "Complete documentation for SNI Router, a TLS/SNI passthrough router built on HAProxy for routing HTTPS traffic by hostname without decrypting.",
    },
  },
});
