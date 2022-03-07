import React from "react";
import ReactDOM from "react-dom";
import "./index.css";
import "@material-tailwind/react/tailwind.css";

import { ThemeProvider } from "./ThemeContext";
import App from "./App";

import reportWebVitals from "./reportWebVitals";

ReactDOM.render(
  <React.StrictMode>
    <ThemeProvider>
      <App />
    </ThemeProvider>
  </React.StrictMode>,
  document.getElementById("root")
);

// If you want to start measuring performance in your app, pass a function
// to log results (for example: reportWebVitals(console.log))
// or send to an analytics endpoint. Learn more: https://bit.ly/CRA-vitals
reportWebVitals();
