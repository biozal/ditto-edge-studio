import ReactDOM from "react-dom/client";
import App from "./App";
import { DittoProvider } from "./providers/DittoProvider";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <DittoProvider>
    <App />
  </DittoProvider>
);
