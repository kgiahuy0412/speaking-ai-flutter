{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    const bootstrap = document.getElementById('innotrik-bootstrap');
    if (bootstrap) {
      bootstrap.classList.add('is-hidden');
      window.setTimeout(() => bootstrap.remove(), 260);
    }
  },
});
