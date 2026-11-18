import { signOut } from "next-auth/react";
import { useRef, useState } from "react";
import { authenticated } from "../session";
import { readCards } from "../store.mjs";

export async function getServerSideProps({ req, res }) {
  res.setHeader("Cache-Control", "private, no-store");
  if (!(await authenticated(req))) return { redirect: { destination: "/auth/signin", permanent: false } };
  try {
    return { props: { initial: readCards(process.env.HOMEPAGE_CONFIG_DIR) } };
  } catch {
    return { props: { initial: null } };
  }
}

const countryNames = new Intl.DisplayNames("ru", { type: "region" });
const countries = (
  "AM AT AU AZ BE BG BR CA CH CN CY CZ DE DK EE ES FI FR GB GE GR HK HU ID IL IN IS IT JP KR KZ LT LU LV MD MX NL NO NZ PL PT RO RS RU SE SG SK TH TR TW UA US UZ VN ZA AE"
).split(" ").map((code) => ({
  icon: String.fromCodePoint(...Array.from(code, (letter) => letter.charCodeAt(0) + 127397)),
  label: code === "US" ? "США" : countryNames.of(code),
})).sort((first, second) => first.label.localeCompare(second.label, "ru"));
const icons = [
  { icon: "🌐", label: "Без страны" },
  ...countries,
  { icon: "🖥️", label: "Сервер" },
  { icon: "🔗", label: "Ссылка" },
];
export default function Dashboard({ initial }) {
  const [data, setData] = useState(initial);
  const [editing, setEditing] = useState(false);
  const [selected, setSelected] = useState(null);
  const [icon, setIcon] = useState("🌐");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const editor = useRef(null);
  const removal = useRef(null);
  const form = useRef(null);
  function open(card, dialog) {
    setSelected(card);
    setError("");
    if (dialog === editor) {
      setIcon(card?.icon || "🌐");
      form.current.elements.name.value = card?.name ?? "";
      form.current.elements.url.value = card?.url ?? "";
      form.current.elements.description.value = card?.description ?? "";
    }
    dialog.current.showModal();
  }
  async function save(op, card, dialog) {
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      const response = await fetch("/api/cards", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ op, original: selected?.name, card, version: data.version }),
      });
      if (response.status === 401) {
        location.replace("/auth/signin");
        return;
      }
      const result = await response.json();
      if (!response.ok) throw Error(result.error);
      setData(result);
      dialog.current.close();
      setMessage(op === "delete" ? "Карточка удалена." : "Карточка сохранена.");
    } catch (e) {
      setError(e.message || "Не удалось сохранить изменения.");
    } finally {
      setBusy(false);
    }
  }
  const alert = error && (
    <p role="alert" className="error">
      {error}
    </p>
  );
  return (
    <>
      <header>
        <div className="brand">
          <img className="brand-logo" src="/cloudpage-logo.png" alt="CloudPage" width="162" height="54" />
        </div>
        <div className="account">
          <span>Личный кабинет</span>
          <button onClick={() => signOut({ callbackUrl: "/auth/signin" })}>Выйти</button>
        </div>
      </header>
      <main>
        <div className="intro">
          <div>
            <h1>Мои серверы</h1>
            <p>Ваши панели. Один удобный вход.</p>
          </div>
          {data && (
            <div className="tools">
              <button aria-pressed={editing} onClick={() => setEditing(!editing)}>
                {editing ? "Готово" : "Редактировать"}
              </button>
              {editing && (
                <button className="primary" onClick={() => open(null, editor)}>
                  + Добавить сервер
                </button>
              )}
            </div>
          )}
        </div>
        {data ? (
          <>
            <div className="group-title">Панели управления · {data.cards.length}</div>
            {editing && <p className="edit-banner">Режим редактирования</p>}
            <div className="grid">
              {data.cards.map((card) => (
                <article key={card.name} className="server">
                  <a href={card.url} target="_blank" rel="noopener noreferrer">
                    <div className="server-top">
                      <span className="flag">{card.icon || "🌐"}</span>
                      <div>
                        <h2>{card.name}</h2>
                        <div className="desc">{card.description}</div>
                      </div>
                    </div>
                    <div className="address">{new URL(card.url).host} · Перейти ↗</div>
                  </a>
                  {editing && (
                    <div className="edit-actions">
                      <button onClick={() => open(card, editor)}>Изменить</button>
                      <button className="danger" onClick={() => open(card, removal)}>
                        Удалить
                      </button>
                    </div>
                  )}
                </article>
              ))}
            </div>
            {!data.cards.length && <p className="empty">Добавьте первую панель сервера.</p>}
          </>
        ) : (
          <p role="alert">Не удалось прочитать services.yaml. Проверьте конфигурацию и обновите страницу.</p>
        )}
        <p className="notice" role="status">
          {message}
        </p>
      </main>
      <dialog ref={editor} aria-labelledby="editor-heading">
        <form
          ref={form}
          className="dialog-body"
          onSubmit={(event) => {
            event.preventDefault();
            save(selected ? "edit" : "add", Object.fromEntries(new FormData(event.currentTarget)), editor);
          }}
        >
          <div className="dialog-heading">
            <h2 id="editor-heading">{selected ? "Изменить сервер" : "Добавить сервер"}</h2>
            <button type="button" className="close-button" aria-label="Закрыть" onClick={() => editor.current.close()}>
              ×
            </button>
          </div>
          <div className="form-pair">
            <div>
              <label htmlFor="icon">Значок</label>
              <select id="icon" name="icon" value={icon} onChange={(event) => setIcon(event.target.value)}>
                {selected?.icon && !icons.some(({ icon }) => icon === selected.icon) && (
                  <option value={selected.icon}>{selected.icon}</option>
                )}
                {icons.map(({ icon, label }) => (
                  <option key={icon} value={icon}>{icon} {label}</option>
                ))}
              </select>
            </div>
            <div>
              <label htmlFor="name">Название</label>
              <input id="name" name="name" required maxLength={60} />
            </div>
          </div>
          <label htmlFor="url">Адрес панели</label>
          <input
            type="url"
            id="url"
            name="url"
            required
            maxLength={2048}
            placeholder="https://server.example.com:2053/panel/"
          />
          <label htmlFor="description">Описание</label>
          <input id="description" name="description" maxLength={120} />
          {alert}
          <div className="dialog-footer">
            <button type="button" onClick={() => editor.current.close()}>
              Отмена
            </button>
            <button className="primary" disabled={busy}>
              Сохранить
            </button>
          </div>
        </form>
      </dialog>
      <dialog ref={removal} aria-labelledby="remove-heading">
        <div className="dialog-body">
          <h2 id="remove-heading">Удалить карточку?</h2>
          <p className="delete-description">
            Карточка «{selected?.name}» исчезнет из кабинета. Сам сервер продолжит работать.
          </p>
          {alert}
          <div className="dialog-footer">
            <button onClick={() => removal.current.close()}>Отмена</button>
            <button className="danger" disabled={busy} onClick={() => save("delete", null, removal)}>
              Удалить карточку
            </button>
          </div>
        </div>
      </dialog>
    </>
  );
}
