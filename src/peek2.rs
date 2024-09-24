use crate::source::*;
use std::path::{Path, PathBuf};

enum Peeked<T> {
    None,
    One(T),
    Two(T, T),
}

impl<T> Peeked<T> {
    fn amount(&self) -> usize {
        match self {
            Peeked::None => 0,
            Peeked::One(_) => 1,
            Peeked::Two(_, _) => 2,
        }
    }
    fn push(&mut self, item: T) {
        *self = match std::mem::replace(self, Self::None) {
            Peeked::None => Peeked::One(item),
            Peeked::One(first) => Peeked::Two(first, item),
            Peeked::Two(_, _) => unreachable!(),
        };
    }
    fn pop(&mut self) -> Option<T> {
        let result;
        (*self, result) = match std::mem::replace(self, Self::None) {
            Peeked::None => (Peeked::None, None),
            Peeked::One(first) => (Peeked::None, Some(first)),
            Peeked::Two(first, second) => (Peeked::One(second), Some(first)),
        };
        result
    }
    fn peek(&self) -> Option<&T> {
        match self {
            Peeked::None => None,
            Peeked::One(first) | Peeked::Two(first, _) => Some(first),
        }
    }
    fn peek2(&self) -> Option<&T> {
        match self {
            Peeked::Two(_, second) => Some(second),
            _ => None,
        }
    }
}

pub struct Reader<T> {
    peeked: Peeked<T>,
    iter: Box<dyn Iterator<Item = T>>,
    current_position: Position,
    filename: PathBuf,
}

pub enum AdvancePosition {
    OneChar(char),
    SetTo(Position),
}

pub trait ReadableItem {
    fn advance_position(&self) -> AdvancePosition;
}

impl ReadableItem for char {
    fn advance_position(&self) -> AdvancePosition {
        AdvancePosition::OneChar(*self)
    }
}

impl Reader<char> {
    pub fn read(source: SourceFile) -> Self {
        Self::new(
            source.filename,
            source.contents.chars().collect::<Vec<char>>(),
        )
    }
}

impl<T: ReadableItem> Reader<T> {
    pub fn new(filename: PathBuf, iter: impl IntoIterator<Item = T> + 'static) -> Self {
        Self {
            peeked: Peeked::None,
            iter: Box::new(iter.into_iter()),
            current_position: Position {
                index: 0,
                line: 1,
                column: 1,
            },
            filename,
        }
    }

    pub fn filename(&self) -> &Path {
        &self.filename
    }

    pub fn peek(&mut self) -> Option<&T> {
        if self.peeked.amount() == 0 {
            if let Some(item) = self.iter.next() {
                self.peeked.push(item);
            }
        }
        self.peeked.peek()
    }

    pub fn peek2(&mut self) -> Option<&T> {
        while self.peeked.amount() < 2 {
            match self.iter.next() {
                Some(item) => self.peeked.push(item),
                None => break,
            }
        }
        self.peeked.peek2()
    }

    pub fn next(&mut self) -> Option<T> {
        let item = self.peeked.pop().or_else(|| self.iter.next());
        if let Some(item) = &item {
            match item.advance_position() {
                AdvancePosition::OneChar(c) => {
                    if c == '\n' {
                        self.current_position.line += 1;
                        self.current_position.column = 1;
                    } else {
                        self.current_position.column += 1;
                    }
                }
                AdvancePosition::SetTo(new_position) => {
                    self.current_position = new_position;
                }
            }
        }
        item
    }

    pub fn position(&self) -> Position {
        self.current_position
    }
}