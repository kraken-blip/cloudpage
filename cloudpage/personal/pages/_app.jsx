import Head from "next/head";
import "../style.css";

export default function App({ Component, pageProps }) {
  return (
    <>
      <Head>
        <title>CloudPage · Мои серверы</title>
        <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon.png" />
      </Head>
      <Component {...pageProps} />
    </>
  );
}
