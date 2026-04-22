import Marketplace from "./components/Marketplace";
import Admin from "./components/Admin";
import UserAccount from "./components/UserAccount";
import PaymentSuccess from "./components/PaymentSuccess";
import AboutUs from "./components/AboutUs";
import ContactUs from "./components/ContactUs";
import { Route } from "./components/Router";
import { CartProvider } from "./contexts/CartContext";

function App() {
  return (
    <CartProvider>
      <Route path="/" element={<Marketplace />} />
      <Route path="/dashboard" element={<UserAccount />} />
      <Route path="/admin" element={<Admin />} />
      <Route path="/payment/success" element={<PaymentSuccess />} />
      <Route path="/about" element={<AboutUs />} />
      <Route path="/contact" element={<ContactUs />} />
    </CartProvider>
  );
}

export default App;
