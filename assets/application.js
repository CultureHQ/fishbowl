self.onload = () => {
  // Service worker registration
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register('service-worker.js');
  }

  // Listen to ⌘+K to clear out mesages
  (function () {
    const messages = document.getElementById("messages");

    document.addEventListener("keydown", event => {
      if (!event.metaKey || String.fromCharCode(event.keyCode) !== "K") {
        return;
      }

      while (messages.firstChild) {
        messages.removeChild(messages.firstChild);
      }
    })
  })();

  // Websocket connection
  (function () {
    const protocol = document.location.protocol === "https:" ? "wss:" : "ws:";
    const websocket = new WebSocket(`${protocol}//${document.location.host}/`);

    const messages = document.getElementById("messages");
    const append = message => {
      let container = document.createElement("div");
      let timestamp = document.createElement("span");
      timestamp.className = "timestamp";

      timestamp.appendChild(document.createTextNode(`[${new Date().toISOString()}]`));
      container.appendChild(timestamp);

      container.appendChild(document.createTextNode(" "));
      container.appendChild(document.createTextNode(message));

      messages.appendChild(container);
    };

    append("Connecting to server...");
    websocket.onopen = () => {
      append("Connection successful.");
      append("Listening for messages...");
    };

    websocket.onclose = () => append("Connection closed.");
    websocket.onerror = () => append("An error occurred.");
    websocket.onmessage = ({ data }) => append(data);
  })();
};
