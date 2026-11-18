import { signIn } from "next-auth/react";
import { useState } from "react";

export default function Login() {
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);
  async function submit(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setPending(true);
    setError("");
    try {
      const result = await signIn("credentials", {
        username: form.get("username"),
        password: form.get("password"),
        redirect: false,
        callbackUrl: "/",
      });
      if (!result?.ok || result.error) throw new Error();
      location.replace("/");
    } catch {
      setError("Не удалось войти. Проверьте логин и пароль.");
    } finally {
      setPending(false);
    }
  }
  return (
    <section className="login">
      <form className="login-box" onSubmit={submit}>
        <div className="brand">
          <img className="brand-logo" src="/cloudpage-logo.png" alt="CloudPage" width="162" height="54" />
        </div>
        <h1>С возвращением.</h1>
        <p>Войдите в свой кабинет серверов.</p>
        <label htmlFor="username">Логин</label>
        <input autoComplete="username" id="username" name="username" required />
        <label htmlFor="password">Пароль</label>
        <input type="password" autoComplete="current-password" id="password" name="password" required />
        <button className="primary" disabled={pending}>
          Войти в кабинет ↗
        </button>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
      </form>
    </section>
  );
}
