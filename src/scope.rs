use std::sync::atomic::AtomicBool;

use super::*;

#[derive(Default)]
pub struct Locals {
    // TODO insertion order
    id_by_name: HashMap<String, Id>,
    by_id: HashMap<Id, (Symbol, Value)>,
}

impl Locals {
    fn new() -> Self {
        Self::default()
    }
    fn insert(&mut self, name: Symbol, value: Value) {
        self.id_by_name.insert(name.name().to_owned(), name.id());
        self.by_id.insert(name.id(), (name, value));
    }
    fn get(&self, lookup: Lookup<'_>) -> Option<&(Symbol, Value)> {
        let id: Id = match lookup {
            Lookup::Name(name) => *self.id_by_name.get(name)?,
            Lookup::Id(id) => id,
        };
        self.by_id.get(&id)
    }
    pub fn iter(&self) -> impl Iterator<Item = &(Symbol, Value)> + '_ {
        self.by_id.values()
    }
}

#[derive(Debug, Copy, Clone)]
pub enum ScopeType {
    NonRecursive,
    Recursive,
}

pub struct Scope {
    pub id: Id,
    pub parent: Option<Parc<Scope>>,
    pub ty: ScopeType,
    closed: AtomicBool,
    closed_event: event_listener::Event,
    pub syntax_definitions: Mutex<Vec<Parc<ast::SyntaxDefinition>>>,
    locals: Mutex<Locals>,
}

impl Drop for Scope {
    fn drop(&mut self) {
        if !*self.closed.get_mut() {
            match self.ty {
                ScopeType::Recursive => {
                    panic!("recursive scope should be closed manually to advance executor")
                }
                ScopeType::NonRecursive => {}
            }
            self.close();
        }
    }
}

#[derive(Copy, Clone)]
pub enum Lookup<'a> {
    Name(&'a str),
    Id(Id),
}

impl std::fmt::Display for Lookup<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Lookup::Name(name) => write!(f, "{name:?}"),
            Lookup::Id(id) => write!(f, "id#{id}"),
        }
    }
}

impl Scope {
    pub fn new(ty: ScopeType, parent: Option<Parc<Self>>) -> Self {
        let id = Id::new();
        tracing::trace!("new scope {id:?} (ty={ty:?})");
        Self {
            id,
            parent,
            ty,
            closed: AtomicBool::new(false),
            closed_event: event_listener::Event::new(),
            syntax_definitions: Default::default(),
            locals: Mutex::new(Locals::new()),
        }
    }
    pub fn close(&self) {
        tracing::trace!("close scope {:?}", self.id);
        self.closed.store(true, std::sync::atomic::Ordering::SeqCst);
        self.closed_event.notify(usize::MAX);
    }
    pub fn inspect<R>(&self, f: impl FnOnce(&Locals) -> R) -> R {
        f(&self.locals.lock().unwrap())
    }
    pub fn insert(&self, name: Symbol, value: Value) {
        self.locals.lock().unwrap().insert(name, value);
    }
    pub fn get_impl<'a>(
        &'a self,
        lookup: Lookup<'a>,
        do_await: bool,
    ) -> BoxFuture<'a, Option<(Symbol, Value)>> {
        tracing::trace!("looking for {lookup} in {:?}", self.id);
        async move {
            loop {
                let was_closed = self.closed.load(std::sync::atomic::Ordering::Relaxed);
                if let Some(result) = self.locals.lock().unwrap().get(lookup).cloned() {
                    tracing::trace!("found {lookup} in ty={:?}", self.ty);
                    return Some(result);
                }
                match self.ty {
                    ScopeType::NonRecursive => {
                        tracing::trace!("non recursive not found {lookup}");
                        break;
                    }
                    ScopeType::Recursive => {}
                }
                if was_closed {
                    break;
                }
                if !do_await {
                    break;
                }
                // TODO maybe wait for the name, not entire scope?
                self.closed_event.listen().await;
                tracing::trace!("continuing searching for {lookup}");
            }
            if let Some(parent) = &self.parent {
                if let Some(value) = parent.get_impl(lookup, do_await).await {
                    return Some(value);
                }
            }
            None
        }
        .boxed()
    }
}
