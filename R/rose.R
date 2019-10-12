#' Apply ROSE algorithm
#'
#' `step_rose` creates a *specification* of a recipe
#'  step that generates sample of synthetic data by enlarging the features
#'  space of minority and majority class example. Using [ROSE::ROSE()].
#'
#' @inheritParams recipes::step_center
#' @param ... One or more selector functions to choose which
#'  variable is used to sample the data. See [selections()]
#'  for more details. The selection should result in _single
#'  factor variable_. For the `tidy` method, these are not
#'  currently used.
#' @param role Not used by this step since no new variables are
#'  created.
#' @param column A character string of the variable name that will
#'  be populated (eventually) by the `...` selectors.
#' @param minority_prop A numeric. Determines the of over-sampling of the
#'  minority class. Defaults to 0.5.
#' @param minority_multiplier A numeric. Shrink factor to be multiplied by the
#'  smoothing parameters to estimate the conditional kernel density of the
#'  minority class. Defaults to 1.
#' @param majority_multiplier A numeric. Shrink factor to be multiplied by the
#'  smoothing parameters to estimate the conditional kernel density of the
#'  majority class. Defaults to 1.
#' @param seed An integer that will be used as the seed when
#' rose-ing.
#' @return An updated version of `recipe` with the new step
#'  added to the sequence of existing steps (if any). For the
#'  `tidy` method, a tibble with columns `terms` which is
#'  the variable used to sample.
#'
#' @details
#' The factor variable used to balance around must only have 2 levels.
#'
#' The ROSE algorithm works by selecting an observation belonging to class k
#' and generates new examples  in its neightborhood is determined by some matrix
#' H_k. Smaller values of these arguments have the effect of shrinking the
#' entries of the corresponding smoothing matrix H_k, Shrinking would be a
#' cautious choice if there is a concern that excessively large neighborhoods
#' could lead to blur the boundaries between the regions of the feature space
#' associated with each class.
#'
#' All columns in the data are sampled and returned by [juice()]
#'  and [bake()].
#'
#' When used in modeling, users should strongly consider using the
#'  option `skip = TRUE` so that the extra sampling is _not_
#'  conducted outside of the training set.
#'
#' @references Lunardon, N., Menardi, G., and Torelli, N. (2014). ROSE: a
#'  Package for Binary Imbalanced Learning. R Jorunal, 6:82–92.
#' @references Menardi, G. and Torelli, N. (2014). Training and assessing
#'  classification rules with imbalanced data. Data Mining and Knowledge
#'  Discovery, 28:92–122.
#'
#' @keywords datagen
#' @concept preprocessing
#' @concept subsampling
#' @export
#' @examples
#' data(okc)
#'
#' sort(table(okc$Class, useNA = "always"))
#'
#' ds_rec <- recipe(Class ~ age + height, data = okc) %>%
#'   step_rose(Class) %>%
#'   prep()
#'
#' table(juice(ds_rec)$Class, useNA = "always")
#'
#' # since `skip` defaults to TRUE, baking the step has no effect
#' baked_okc <- bake(ds_rec, new_data = okc)
#' table(baked_okc$Class, useNA = "always")
#'
#' ds_rec2 <- recipe(Class ~ age + height, data = okc) %>%
#'   step_rose(Class, minority_prop = 0.3) %>%
#'   prep()
#'
#' table(juice(ds_rec2)$Class, useNA = "always")
#'
#' @importFrom recipes rand_id add_step ellipse_check
step_rose <-
  function(recipe, ..., role = NA, trained = FALSE,
           column = NULL, minority_prop = 0.5, minority_multiplier = 1, majority_multiplier = 1,
           skip = TRUE, seed = sample.int(10^5, 1), id = rand_id("rose")) {

    add_step(recipe,
             step_rose_new(
               terms = ellipse_check(...),
               role = role,
               trained = trained,
               column = column,
               minority_prop = minority_prop,
               minority_multiplier = minority_multiplier,
               majority_multiplier = majority_multiplier,
               skip = skip,
               seed = seed,
               id = id
             ))
  }

#' @importFrom recipes step
step_rose_new <-
  function(terms, role, trained, column, minority_prop, minority_multiplier, majority_multiplier, skip,
           seed, id) {
    step(
      subclass = "rose",
      terms = terms,
      role = role,
      trained = trained,
      column = column,
      minority_prop = minority_prop,
      minority_multiplier = minority_multiplier,
      majority_multiplier = majority_multiplier,
      skip = skip,
      id = id,
      seed = seed,
      id = id
    )
  }

#' @importFrom recipes bake prep check_type
#' @importFrom dplyr select
#' @export
prep.step_rose <- function(x, training, info = NULL, ...) {

  col_name <- terms_select(x$terms, info = info)
  if (length(col_name) != 1)
    stop("Please select a single factor variable.", call. = FALSE)
  if (!is.factor(training[[col_name]]))
    stop(col_name, " should be a factor variable.", call. = FALSE)
  if (length(levels(training[[col_name]])) != 2)
    stop(col_name, " must only have 2 levels.", call. = FALSE)

  check_type(select(training, -col_name), TRUE)

  step_rose_new(
    terms = x$terms,
    role = x$role,
    trained = TRUE,
    column = col_name,
    minority_prop = x$minority_prop,
    minority_multiplier = x$minority_multiplier,
    majority_multiplier = x$majority_multiplier,
    skip = x$skip,
    seed = x$seed,
    id = x$id
  )
}


#' @importFrom tibble as_tibble tibble
#' @importFrom withr with_seed
#' @importFrom ROSE ROSE
#' @export
bake.step_rose <- function(object, new_data, ...) {
  if (any(is.na(new_data[[object$column]])))
    missing <- new_data[is.na(new_data[[object$column]]),]
  else
    missing <- NULL
  split_up <- split(new_data, new_data[[object$column]])

  new_data <- as.data.frame(new_data)
  # rose with seed for reproducibility
  with_seed(
    seed = object$seed,
    code = {
      new_data <- ROSE(string2formula(object$column), new_data,
                       p = object$minority_prop,
                       hmult.majo = object$majority_multiplier,
                       hmult.mino = object$minority_multiplier)$data
    }
  )

  as_tibble(new_data)
}

#' @importFrom recipes printer terms_select
#' @export
print.step_rose <-
  function(x, width = max(20, options()$width - 26), ...) {
    cat("ROSE based on ", sep = "")
    printer(x$column, x$terms, x$trained, width = width)
    invisible(x)
  }

#' @rdname step_rose
#' @param x A `step_rose` object.
#' @importFrom generics tidy
#' @importFrom recipes sel2char is_trained
#' @export
tidy.step_rose <- function(x, ...) {
  if (is_trained(x)) {
    res <- tibble(terms = x$column)
  }
  else {
    term_names <- sel2char(x$terms)
    res <- tibble(terms = unname(term_names))
  }
  res$id <- x$id
  res
}