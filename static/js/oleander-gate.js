(() => {
  "use strict";

  const storageKey = "gwokhiujin:oleander:unlocked";
  const passwordHash = "eb584742dfe328c410e35951f9858d2a7b34a5d5d1839cd3711a22e8c7653d7e";
  const gate = document.getElementById("oleander-gate");
  const protectedContent = document.getElementById("oleander-protected");
  const form = document.getElementById("oleander-gate-form");
  const input = document.getElementById("oleander-password");
  const error = document.getElementById("oleander-gate-error");

  if (!gate || !protectedContent || !form || !input || !error) return;

  const unlock = () => {
    gate.hidden = true;
    protectedContent.hidden = false;
    document.body.classList.remove("oleander-locked");
    document.getElementById("main-content")?.focus({ preventScroll: true });
  };

  try {
    if (sessionStorage.getItem(storageKey) === "true") {
      unlock();
      return;
    }
  } catch (_) {
    // Storage can be unavailable in strict privacy modes; the gate still works.
  }

  input.focus({ preventScroll: true });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    error.textContent = "";

    const password = input.value;
    if (!/^[a-z]{5}$/.test(password)) {
      error.textContent = "请输入 5 个小写英文字母。";
      input.focus();
      return;
    }

    if (!window.crypto?.subtle) {
      error.textContent = "当前浏览器无法验证密码，请更换浏览器后重试。";
      return;
    }

    const bytes = new TextEncoder().encode(password);
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    const actualHash = Array.from(new Uint8Array(digest), (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");

    if (actualHash !== passwordHash) {
      error.textContent = "密码不正确。";
      input.select();
      return;
    }

    try {
      sessionStorage.setItem(storageKey, "true");
    } catch (_) {
      // Unlock the current page even when session storage is unavailable.
    }
    unlock();
  });
})();
