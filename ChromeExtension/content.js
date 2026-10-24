// Sayfalardaki magnet: linklerine tıklamayı yakalar. Tarayıcı bu linkleri indirme olarak değil,
// "hangi uygulama açsın" sorusu olarak ele aldığı için indirme dinleyicisi bunları göremiyor.
// Uygulama kabul etmezse (kapalıysa) link normal şekilde açılır.
(() => {
  const MAGNET = /^magnet:/i;

  function magnetLink(event) {
    const link = event.target instanceof Element ? event.target.closest("a[href]") : null;
    return link && MAGNET.test(link.href) ? link.href : null;
  }

  async function handle(event) {
    // Sadece sol ve orta tık; değiştirici tuşlarla tıklayan kullanıcı tarayıcının davranışını istiyor olabilir.
    if (event.button > 1 || event.altKey || event.metaKey || event.ctrlKey || event.shiftKey) return;
    const url = magnetLink(event);
    if (!url) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    let accepted = false;
    try {
      accepted = await chrome.runtime.sendMessage({ type: "magnet", url, referrer: location.href });
    } catch {
      // Eklenti yeniden yüklendiyse bu sayfadaki betik eski kalır; normal açılışa bırak.
    }
    if (!accepted) {
      location.href = url;
    }
  }

  document.addEventListener("click", handle, true);
  document.addEventListener("auxclick", handle, true);
})();
