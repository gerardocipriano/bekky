// Caricato nell'head: applica il tema salvato prima del primo paint.
try {
  var t = localStorage.getItem("bekky-theme");
  if (t === "light" || t === "dark") document.documentElement.setAttribute("data-theme", t);
} catch (e) { /* senza storage resta il tema del sistema */ }
