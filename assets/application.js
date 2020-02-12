"use strict";

self.onload = function () {
  // Service worker registration
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("service-worker.js");
  }

  // Listen to ⌘+K to clear out messages
  (function () {
    var messages = document.getElementById("messages");

    document.addEventListener("keydown", function (event) {
      if (!event.metaKey || String.fromCharCode(event.keyCode) !== "K") {
        return;
      }

      while (messages.firstChild) {
        messages.removeChild(messages.firstChild);
      }
    });
  })();

  // Websocket connection
  (function () {
    var protocol = document.location.protocol === "https:" ? "wss:" : "ws:";
    var websocket = new WebSocket(protocol + "//" + document.location.host + "/");

    var messages = document.getElementById("messages");
    var append = function (message) {
      var container = document.createElement("div");
      var timestamp = document.createElement("span");

      timestamp.className = "timestamp";
      timestamp.appendChild(document.createTextNode("[" + new Date().toISOString() + "]"));

      container.appendChild(timestamp);
      container.appendChild(document.createTextNode(" "));
      container.appendChild(document.createTextNode(message));

      messages.appendChild(container);
    };

    append("Connecting to server...");

    websocket.onopen = function () {
      append("Connection successful.");
      append("Listening for messages...");
    };

    websocket.onclose = function () {
      append("Connection closed.");
    };

    websocket.onerror = function () {
      append("An error occurred.");
    };

    websocket.onmessage = function (message) {
      append(message.data);
    };
  })();
};
