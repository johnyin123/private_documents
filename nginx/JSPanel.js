"use strict";
class JSPanel {
  constructor(button, options) {
    this.panel = null;
    this.button = button;
    this.options = options;
    this.panel_uniqueid = "jspanel-" + this._rand(0, 1000000);
    this._buildPanel();
    this.button.setAttribute("aria-expanded", "false");
    this.button.setAttribute("aria-controls", this.panel_uniqueid);
  }
  _buildPanel() {
    const top = this.options.top === undefined ? null : this.options.top + "px";
    const right = this.options.right === undefined ? null : this.options.right + "px";
    const bottom = this.options.bottom === undefined ? null : this.options.bottom + "px";
    const left = this.options.left === undefined ? null : this.options.left + "px";
    this.panel = this._createEl("div", { id: this.panel_uniqueid, className: "jspanel panel-hidden" });
    if (top || right || bottom || left) {
      if (top)
        this.panel.style.top = top;
      if (left)
        this.panel.style.left = left;
      if (right)
        this.panel.style.right = right;
      if (bottom)
        this.panel.style.bottom = bottom;
    }
    else {
      this.panel.style.top = "0px";
      this.panel.style.left = "0px";
    }
    const parent = this.button.parentElement === null ? document.body : this.button.parentElement;
    const style_position = window.getComputedStyle(parent).getPropertyValue("position");
    if (!this._inArray(style_position, ["fixed", "absolute", "relative"]))
      parent.style.position = "relative";
    if (this.options.items) {
      const container = this._createEl("div", { className: "container-items" });
      for (let i = 0; i < this.options.items.length; i++) {
        const item = this.options.items[i];
        if (item) {
          if (!item.id)
            item.id = i;
          const built_item = this._buildItem(item);
          container.appendChild(built_item);
        }
      }
      this.panel.appendChild(container);
    }
    else {
      throw new Error("You need to define items to be displayed in the panel.");
    }
    document.addEventListener("click", (e) => {
      const target = e.target;
      if (target && this.panel) {
        if (!this.panel.contains(target) && this.isOpen()) {
          this._closePanel();
        }
      }
    });
    this.button.onclick = (e) => { this._togglePanel(e); };
    this.button.onkeydown = (e) => { this._toggleOnKeyboardEvent(e); };
    this._insertAfterButton(this.panel);
    this.panel.onkeydown = (e) => {
      if (e.key === "Tab" || e.keyCode === 9) {
        if (this.isOpen())
          this._focusInPanel(e);
      }
    };
    this.button.onkeydown = (e) => {
      if (e.key === "Tab" || e.keyCode === 9) {
        if (this.isOpen()) {
          e.preventDefault();
          const active_elements = this._getAllActiveItems();
          if (active_elements && active_elements[0]) {
            if (e.shiftKey === true) {
              active_elements[active_elements.length - 2].focus(); // -2 because we don't want to take into account the button once again
            }
            else {
              active_elements[0].focus();
            }
          }
        }
      }
    };
  }
  _toggleOnKeyboardEvent(e) {
    if (e.key === "Enter" || e.code === "Enter" || e.keyCode === 13 || e.key === " " || e.keyCode === 32 || e.code === "Space") {
      e.preventDefault();
      this._togglePanel(e);
    }
  }
  isOpen() {
    if (this.panel) {
      return !this.panel.classList.contains("panel-hidden");
    }
    else {
      return false;
    }
  }
  _togglePanel(e) {
    if (this.button && this.panel) {
      e.stopPropagation();
      if (this.isOpen()) {
        this._closePanel();
      }
      else {
        this.button.setAttribute("aria-expanded", "true");
        this.panel.classList.remove("panel-hidden");
        const all_items = this._getAllItems();
        if (all_items && all_items[0])
          all_items[0].focus();
      }
    }
  }
  _getAllItems() {
    if (this.isOpen()) {
      return this.panel.querySelectorAll("button");
    }
    else {
      return null;
    }
  }
  _getAllActiveItems() {
    if (this.isOpen()) {
      const active_elements = Array.from(this.panel.querySelectorAll("button"));
      active_elements.push(this.button);
      return active_elements.filter((e) => e.style.display !== "none" && !e.hasAttribute("disabled"));
    }
    else {
      return null;
    }
  }
  _closePanel() {
    if (this.button && this.panel) {
      this.button.setAttribute("aria-expanded", "false");
      this.panel.classList.add("panel-hidden");
    }
  }
  _createEl(tagName, options) {
    const el = document.createElement(tagName);
    if (!options)
      return el;
    if (options.id)
      el.setAttribute("id", options.id);
    if (options.textContent)
      el.textContent = options.textContent;
    if (options.className) {
      const classes = options.className.split(" ");
      for (let clas of classes) {
        el.classList.add(clas);
      }
    }
    if (options.styles) {
      for (let style of options.styles) {
        const property = style[0];
        const value = style[1];
        el.style[property] = value;
      }
    }
    if (options.attributes) {
      for (let attr of options.attributes) {
        const name = attr[0];
        const value = attr[1];
        el.setAttribute(name, value);
      }
    }
    return el;
  }
  _buildItem(item) {
    const id = item.id.toString();
    if (item.separator) {
      const div = this._createEl("div", { className: 'jspanel-separator', attributes: [["data-id", id]] });
      return div;
    }
    else {
      const button = this._createEl("button");
      button.setAttribute("data-id", id);
      button.setAttribute("aria-label", item.title);
      if ((item.icon && !item.fontawesome_icon) || (item.icon && item.fontawesome_icon)) {
        const icon = this._createEl("img", { attributes: [["src", item.icon]] });
        button.appendChild(icon);
      }
      else if (!item.icon && item.fontawesome_icon) {
        const icon = this._createEl("i", { className: item.fontawesome_icon });
        if (item.fontawesome_color)
          icon.style.color = item.fontawesome_color;
        button.appendChild(icon);
      }
      if (item.className) {
        const classes = item.className.split(" ");
        for (let clas of classes) {
          button.classList.add(clas);
        }
      }
      if (item.attributes) {
        for (let attr of item.attributes) {
          const name = attr[0];
          const value = attr[1];
          button.setAttribute(name, value);
        }
      }
      const title = this._createEl("span", { textContent: item.title });
      button.appendChild(title);
      button.addEventListener('click', () => {
        if (item.onclick)
          item.onclick();
        this._closePanel();
      });
      return button;
    }
  }
  _focusInPanel(e) {
    const all_items = this._getAllActiveItems();
    if (all_items) {
      e.preventDefault();
      let index = Array.from(all_items).findIndex(f => this.panel ? f === this.panel.querySelector(":focus") : false);
      if (e.shiftKey === true) {
        index--;
      }
      else {
        index++;
      }
      if (index >= all_items.length) {
        index = 0;
      }
      if (index < 0) {
        index = all_items.length - 1;
      }
      all_items[index].focus();
    }
  }
  _inArray(needle, haystack, strict = false) {
    const length = haystack.length;
    for (let i = 0; i < length; i++) {
      if (strict) {
        if (haystack[i] === needle)
          return true;
      }
      else {
        if (haystack[i] == needle)
          return true;
      }
    }
    return false;
  }
  _insertAfterButton(panel) {
    const parent = this.button.parentElement === null ? document.body : this.button.parentElement;
    parent.insertBefore(panel, this.button.nextSibling);
  }
  _rand(min, max) {
    min = Math.ceil(min);
    max = Math.floor(max);
    return Math.floor(Math.random() * (max - min)) + min;
  }
  toggleItem(id, disable = false) {
    if (this.panel) {
      const items = Array.from(this.panel.querySelectorAll("[data-id='" + id + "']"));
      if (disable) {
        if (items)
          for (let item of items) {
            if (item.tagName.toLowerCase() === "button") {
              item.hasAttribute("disabled") ? item.removeAttribute("disabled") : item.setAttribute("disabled", "disabled");
            }
            else {
              if (items)
                for (let item of items)
                  item.style.display = item.style.display == "none" ? null : "none";
            }
          }
      }
      else {
        if (items)
          for (let item of items)
            item.style.display = item.style.display == "none" ? null : "none";
      }
    }
  }
  removeItem(id) {
    if (this.panel) {
      const item = this.getItem(id);
      if (item && item.parentElement) {
        item.parentElement.removeChild(item);
      }
    }
  }
  removeItems(ids) {
    if (this.panel) {
      for (let id of ids) {
        this.removeItem(id);
      }
    }
  }
  getAllIDS() {
    if (this.panel) {
      const all_items = Array.from(this.panel.querySelectorAll("[data-id]"));
      const all_ids = [];
      if (all_items) {
        for (let item of all_items) {
          all_ids.push(parseInt(item.getAttribute("data-id")));
        }
        return all_ids;
      }
    }
    return [];
  }
  getItem(id) {
    if (this.panel) {
      return this.panel.querySelector("[data-id='" + id + "']");
    }
    return null;
  }
  _buildNewItem(new_item, default_new_id) {
    if (!new_item.id && (default_new_id === null || default_new_id === undefined))
      throw new Error("An item must have an ID.");
    if (!new_item.id)
      new_item.id = default_new_id;
    const build_item = this._buildItem(new_item);
    return build_item;
  }
  addItem(new_item) {
    if (this.panel) {
      this.panel.appendChild(this._buildNewItem(new_item, Math.max(...this.getAllIDS())));
    }
  }
  replaceItemWith(new_item, id) {
    if (this.panel) {
      const current_item = this.getItem(id);
      if (current_item) {
        const new_built_item = this._buildNewItem(new_item, parseInt(current_item.getAttribute("data-id")));
        current_item.replaceWith(new_built_item);
      }
    }
  }
  deletePanel() {
    if (this.panel && this.panel.parentElement) {
      this.panel.parentElement.removeChild(this.panel);
      this._closePanel();
      this.panel = null;
    }
  }
}
