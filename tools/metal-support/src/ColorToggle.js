import React from "react";
import { FaSun, FaMoon } from "react-icons/fa";
import { ThemeContext } from "./ThemeContext";

const ColorToggle = () => {
  const { theme, setTheme } = React.useContext(ThemeContext);

  return (
    <div className="transition duration-500 ease-in-out rounded-full mt-3 mr-3">
      {theme === "dark" ? (
        <FaSun
          onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
          className="text-gray-500 dark:text-gray-400 text-2xl cursor-pointer"
        />
      ) : (
        <FaMoon
          onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
          className="text-gray-500 dark:text-gray-400 text-2xl cursor-pointer"
        />
      )}
    </div>
  );
};

export default ColorToggle;
