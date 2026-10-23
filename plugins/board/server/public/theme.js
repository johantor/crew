// Runs before first paint so a saved theme never flashes. "auto" (or nothing
// saved) follows the browser's prefers-color-scheme.
(function () {
  var choice = 'auto';
  try {
    choice = localStorage.getItem('board-theme') || 'auto';
  } catch (e) {
    // Storage blocked: follow the browser.
  }
  if (choice === 'light' || choice === 'dark') document.documentElement.dataset.theme = choice;
})();
