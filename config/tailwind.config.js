module.exports = {
  darkMode: 'class',  // ← on active le mode manuel via classe CSS
  content: [
    './app/views/**/*.html.erb',
    './app/views/**/*.erb',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/assets/stylesheets/**/*.css',
  ],
  theme: { extend: {} },
  plugins: [],
}
